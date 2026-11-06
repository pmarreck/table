-- Independent conversion core; the native library supplies OS/Unicode primitives.
local ffi=require('ffi')
local config=require('table_config')
ffi.cdef[[
typedef struct { unsigned char *data; size_t len; } TableBytes;
typedef struct { TableBytes out, err; int status; } TableProcess;
void table_free(void *); int table_read(TableBytes *); int table_write(int,const unsigned char *,size_t);
const char *table_about(void); const char *table_renderer(void); uint64_t table_columns(void);
int table_tty(void); uint64_t table_env_columns(void);
int table_next(const unsigned char *,size_t,int32_t *); int table_white(int32_t); int table_safe(int32_t);
int64_t table_width(const unsigned char *,size_t);
int table_process(const char *,char *const *,const unsigned char *,size_t,int,TableProcess *);
]]
local native=ffi.load(config.native)
local function fail(s) error(s,0) end
local function chars(s)
    local result,i={},1; local bytes=ffi.cast('const unsigned char *',s)
    while i<=#s do
        local cp=ffi.new('int32_t[1]'); local n=native.table_next(bytes+i-1,#s-i+1,cp)
        if n<=0 then fail('input is not UTF-8') end
        result[#result+1]={s:sub(i,i+n-1),tonumber(cp[0])}; i=i+n
    end
    return result
end
local function trim(s,only_space)
    local c=chars(s); local a,b=1,#c
    local function white(v) return only_space and v==32 or not only_space and native.table_white(v)~=0 end
    while a<=b and white(c[a][2]) do a=a+1 end
    while b>=a and white(c[b][2]) do b=b-1 end
    local out={}; for i=a,b do out[#out+1]=c[i][1] end; return table.concat(out)
end
local function split(s,delimiter)
    local out,start={},1
    while true do local a,b=s:find(delimiter,start,true); if not a then out[#out+1]=s:sub(start); return out end; out[#out+1]=s:sub(start,a-1); start=b+1 end
end
local function lines(s)
    local out=split(s,'\n'); if out[#out]=='' then out[#out]=nil end
    for i,v in ipairs(out) do out[i]=v:gsub('\r$','') end
    return out
end
local function validate(t)
    local width
    for _,row in ipairs(t.rows) do
        if #row==0 then fail('rows must contain at least one field') end
        if width and width~=#row then fail('ragged rows') end; width=#row
    end
    return t
end
local function delimited(s,csv,header)
    local rows,row,field={},{},{}; local quoted,closed,started=false,false,false; local i=1
    local function push() row[#row+1]=table.concat(field); field={} end
    while i<=#s do
        local c=s:sub(i,i); i=i+1
        if quoted then
            if c=='"' then if s:sub(i,i)=='"' then i=i+1; field[#field+1]='"' else quoted=false; closed=true end else field[#field+1]=c end
        elseif c==(csv and ',' or '\t') then push(); closed=false; started=true
        elseif c=='\n' or c=='\r' then
            if c=='\r' then if s:sub(i,i)~='\n' then fail('bare carriage return outside quoted field') end; i=i+1 end
            push(); rows[#rows+1]=row; row={}; closed=false; started=false
        elseif csv and c=='"' then
            if #field>0 or closed then fail('unexpected quote') end; quoted=true; started=true
        else if closed then fail('characters after closing quote') end; field[#field+1]=c; started=true end
    end
    if quoted then fail('unterminated quoted field') end
    if started or closed then push(); rows[#rows+1]=row end
    return validate({rows=rows,header=header and #rows>0})
end
local escapes={[27]='e',[28]='f',[29]='g',[30]='r',[31]='u'}
local unescape={e=27,f=28,g=29,r=30,u=31}
local function ir_encode(t)
    validate(t); local out={'\28T1'}; if t.header then out[#out+1]='\29' end
    for _,row in ipairs(t.rows) do
        for j,field in ipairs(row) do
            if j>1 then out[#out+1]='\31' end
            for i=1,#field do local b=field:byte(i); out[#out+1]=escapes[b] and '\27'..escapes[b] or string.char(b) end
        end
        out[#out+1]='\30'
    end
    out[#out+1]='\28'; return table.concat(out)
end
local function ir_decode(s)
    if s:sub(1,3)~='\28T1' then fail('invalid intermediate signature') end
    local i,header=4,false; if s:byte(i)==29 then header=true; i=i+1 end
    local rows,row,field={},{},{}; local started=false
    while true do
        local b=s:byte(i); if not b then fail('missing intermediate terminator') end; i=i+1
        if b==28 and not started then if i~=#s+1 then fail('trailing intermediate bytes') end; break
        elseif b==28 or b==29 then fail('unexpected structural marker')
        elseif b==30 or b==31 then
            local f=table.concat(field); local ok=pcall(chars,f); if not ok then fail('invalid UTF-8 field') end
            row[#row+1]=f; field={}
            if b==30 then rows[#rows+1]=row; row={}; started=false else started=true end
        elseif b==27 then
            local code=s:sub(i,i); if code=='' then fail('incomplete escape') end; i=i+1
            if not unescape[code] then fail('invalid escape') end
            field[#field+1]=string.char(unescape[code]); started=true
        else field[#field+1]=string.char(b); started=true end
    end
    if header and #rows==0 then fail('header marker without row') end
    return validate({rows=rows,header=header})
end
local function write_delimited(t,csv,sanitize)
    validate(t); local out={}
    for _,row in ipairs(t.rows) do
        for j,cell in ipairs(row) do
            if j>1 then out[#out+1]=csv and ',' or '\t' end
            if sanitize then cell=cell:gsub('[\t\r\n]','�') end
            if csv and cell:find('[,"\r\n]') then out[#out+1]='"'..cell:gsub('"','""')..'"'
            elseif not csv and not sanitize and cell:find('[\t\r\n]') then fail('TSV cannot represent tabs or newlines in a field')
            else out[#out+1]=cell end
        end
        out[#out+1]='\n'
    end
    return table.concat(out)
end
local function punctuation(c) local b=c:byte(); return b and b>=33 and b<=126 and not c:match('[%w]') end
local function md_cells(line)
    local s=trim(line); if s:sub(1,1)=='|' then s=s:sub(2) end
    local row,field={},{}; local i,last=1,false
    while i<=#s do
        local c=s:sub(i,i); i=i+1
        if c=='\\' then local next=s:sub(i,i); if punctuation(next) then i=i+1; field[#field+1]=next else field[#field+1]=c end; last=false
        elseif c=='|' then row[#row+1]=trim(table.concat(field)); field={}; last=true
        else field[#field+1]=c; last=false end
    end
    if not last then row[#row+1]=trim(table.concat(field)) end
    if #row==0 then fail('Markdown row has no cells') end; return row
end
local function markdown(s)
    if s=='' then fail('Markdown requires a header and delimiter row') end
    local ls=lines(s)
    local function clean(line)
        for _,c in ipairs(chars(line)) do if c[2]<32 and c[2]~=9 or c[2]>=127 and c[2]<=159 then fail('control character in Markdown row') end end
        return line
    end
    local header=md_cells(clean(ls[1])); if not ls[2] then fail('missing Markdown delimiter row') end
    local divider=md_cells(clean(ls[2])); if #divider~=#header then fail('invalid Markdown delimiter row') end
    for _,c in ipairs(divider) do if not c:gsub('^:',''):gsub(':$',''):match('^%-%-%-+%-$') and not c:gsub('^:',''):gsub(':$',''):match('^%-%-%-$') then fail('invalid Markdown delimiter row') end end
    local rows={header}; for i=3,#ls do rows[#rows+1]=md_cells(clean(ls[i])) end
    return validate({rows=rows,header=true})
end
local function write_markdown(t)
    validate(t); if not t.header then fail('Markdown requires a header') end
    local out={}
    for i,row in ipairs(t.rows) do
        out[#out+1]='|'
        for _,cell in ipairs(row) do
            if trim(cell)~=cell then fail('Markdown cannot preserve edge whitespace or control characters in a cell') end
            local escaped={}; for _,c in ipairs(chars(cell)) do
                if c[2]<32 or c[2]>=127 and c[2]<=159 then fail('Markdown cannot preserve edge whitespace or control characters in a cell') end
                escaped[#escaped+1]=(punctuation(c[1]) and '\\' or '')..c[1]
            end
            out[#out+1]=' '..table.concat(escaped)..' |'
        end
        out[#out+1]='\n'
        if i==1 then out[#out+1]='|'..string.rep(' --- |',#row)..'\n' end
    end
    return table.concat(out)
end
local function visual(s,ansi,spec)
    local out={}; local i=1
    while i<=#s do local c=s:sub(i,i); i=i+1
        if c=='\27' then
            if not ansi or s:sub(i,i)~='[' then fail('unsupported terminal escape') end; i=i+1; local count=0
            while s:sub(i,i)~='m' do
                if count>=128 or not s:sub(i,i):match('^[%d;]$') then fail('unsupported terminal escape') end
                count=count+1; i=i+1
            end; i=i+1
        else out[#out+1]=c end
    end
    s=table.concat(out); if s=='' then return {rows={},header=false} end
    local ls=lines(s); if #ls<3 then fail('incomplete visual table') end
    local glyphs
    if spec then
        glyphs=split(spec,','); for _,g in ipairs(glyphs) do local c=chars(g); if #c~=1 or c[2] or native.table_white(c[1][2])~=0 or native.table_safe(c[1][2])==0 or tonumber(native.table_width(g,#g))~=1 then fail('custom visual glyphs must be single, safe, one-cell non-whitespace characters other than comma') end end
        if #glyphs~=11 then fail('custom visual glyphs require 11 comma-separated characters') end
        for j=1,9 do if glyphs[j]==glyphs[10] or glyphs[j]==glyphs[11] then fail('custom line, vertical and junction glyphs must be distinct') end end
        if glyphs[10]==glyphs[11] then fail('custom line, vertical and junction glyphs must be distinct') end
    elseif ansi and ls[1]:sub(1,#'┌')=='┌' then glyphs={'┌','┬','┐','├','┼','┤','└','┴','┘','─','│'}
    elseif ls[1]:sub(1,1)=='+' then glyphs={'+','+','+','+','+','+','+','+','+','-','|'}
    else fail('unrecognized visual border; provide explicit glyphs') end
    local function border(line,k)
        local c=chars(line); if not c[1] or c[1][1]~=glyphs[k] then fail('invalid table border') end
        local widths,w={},0
        for j=2,#c do
            if c[j][1]==glyphs[10] then w=w+1
            elseif c[j][1]==glyphs[k+1] and j<#c or c[j][1]==glyphs[k+2] and j==#c then
                if w<3 then fail('table border column is too narrow') end; widths[#widths+1]=w; w=0
            else fail('invalid table border character') end
        end
        if c[#c][1]~=glyphs[k+2] or w~=0 or #widths==0 then fail('incomplete table border') end
        return widths
    end
    local function same(a,b) if #a~=#b then return false end; for j,v in ipairs(a) do if v~=b[j] then return false end end; return true end
    local widths=border(ls[1],1); if not same(widths,border(ls[#ls],7)) then fail('bottom border width mismatch') end
    local rows,header,divider={},false,false; local v=glyphs[11]
    for j=2,#ls-1 do local line=ls[j]
        if line:sub(1,#v)==v then
            if line:sub(-#v)~=v then fail('invalid table row boundary') end
            local fields=split(line:sub(#v+1,-#v-1),v); if #fields~=#widths then fail('ambiguous vertical delimiter in table row') end
            for k,f in ipairs(fields) do
                for _,c in ipairs(chars(f)) do if native.table_safe(c[2])==0 then fail('control or unsafe format character in visual cell') end end
                if tonumber(native.table_width(f,#f))~=widths[k] or f:sub(1,1)~=' ' or f:sub(-1)~=' ' then fail('table row does not match border widths') end
                fields[k]=trim(f,true)
            end
            rows[#rows+1]=fields
        else
            if divider or #rows~=1 or not same(widths,border(line,4)) then fail('ambiguous or misplaced table separator') end
            header=true; divider=true
        end
    end
    if #rows==0 then fail('visual table has no rows') end
    return validate({rows=rows,header=header})
end
local function parse(format,s,header,glyphs)
    if format=='ir' then return ir_decode(s) end
    chars(s)
    if format=='csv' or format=='tsv' then return delimited(s,format=='csv',header) end
    if format=='markdown' then return markdown(s) end
    return visual(s,format=='ansi',glyphs)
end
local formats={csv=true,tsv=true,markdown=true,ir=true,ascii=true,ansi=true}
local function detect(s,glyphs)
    if s:sub(1,3)=='\28T1' then ir_decode(s); return 'ir' end
    chars(s); local candidates={}
    if pcall(markdown,s) then candidates[#candidates+1]='markdown' end
    if s~='' then if pcall(visual,s,false,glyphs) then candidates[#candidates+1]='ascii' elseif pcall(visual,s,true,glyphs) then candidates[#candidates+1]='ansi' end end
    for _,f in ipairs({'csv','tsv'}) do local ok,t=pcall(delimited,s,f=='csv',false); if ok and t.rows[1] and #t.rows[1]>1 then candidates[#candidates+1]=f end end
    if #candidates==0 then fail('cannot detect input format; specify --from (empty or single-column input needs an explicit format)') end
    if #candidates>1 then fail('ambiguous input format; specify --from csv, tsv, markdown, ir, ascii, or ansi') end
    return candidates[1]
end
local help='Usage: table [--from auto|csv|tsv|markdown|ir|ascii|ansi] --to csv|tsv|markdown|ir|ascii|ansi [--header|--no-header]\nInput format is detected when --from is omitted. Ambiguous input requires --from.\nAutodetection buffers stdin; explicit --from tsv retains fixed-width visual streaming.\nVisual output: --widths, --align, --overflow, --terminal-width, --color, --plain, --decimal-separator.\n'
local function output(stream,s) if native.table_write(stream,s,#s)~=0 then fail('output write failed') end end
local function input() local b=ffi.new('TableBytes[1]'); if native.table_read(b)~=0 then fail('input read failed') end; local s=ffi.string(b[0].data,b[0].len); native.table_free(b[0].data); return s end
local function renderer()
    local path=arg[0]:gsub('[/\\][^/\\]+$',''); local suffix=ffi.os=='Windows' and '.exe' or ''
    for _,p in ipairs({path..'/libexec/tsv-to-ansi-table'..suffix,path..'/../libexec/tsv-to-ansi-table'..suffix}) do local f=io.open(p,'rb'); if f then f:close(); return p end end
    return config.renderer
end
local function render(data,inherit,ascii,header,options)
    local program=renderer(); local args={program}; if not header then args[#args+1]='--no-header' end; if ascii then args[#args+1]='--ascii' end
    for _,v in ipairs(options) do args[#args+1]=v end
    local argv=ffi.new('char *[?]',#args+1); for i,v in ipairs(args) do argv[i-1]=ffi.cast('char *',v) end
    local result=ffi.new('TableProcess[1]')
    if native.table_process(program,argv,data or '',data and #data or 0,inherit and 1 or 0,result)~=0 then fail('cannot start renderer') end
    local r=result[0]; local stdout=r.out.data~=nil and ffi.string(r.out.data,r.out.len) or ''; local stderr=r.err.data~=nil and ffi.string(r.err.data,r.err.len) or ''
    native.table_free(r.out.data); native.table_free(r.err.data)
    if r.status~=0 then fail(inherit and ('renderer exited with exit status: '..r.status) or 'renderer: '..trim(stderr)) end
    return stdout
end
local function run()
    local from,to,glyphs; local header,header_explicit,allow,color=true,false,false,false; local opts={}; local i=1
    local function auto_color() return native.table_tty()~=0 and not os.getenv('NO_COLOR') and os.getenv('TERM')~='dumb' end
    while i<=#arg do
        local a=arg[i]; i=i+1; local key,value=a:match('^([^=]+)=(.*)$'); key=key or a
        local function val() if value~=nil then return value end; local v=arg[i]; if not v then fail(key..' requires a value') end; i=i+1; return v end
        if key=='--from' then from=val() elseif key=='--to' then to=val() elseif key=='--visual-glyphs' then glyphs=val()
        elseif key=='--allow-lossy' and value==nil then allow=true
        elseif key=='--header' and value==nil then header=true; header_explicit=true
        elseif key=='--no-header' and value==nil then header=false; header_explicit=true
        elseif key=='--about' and value==nil then output(1,ffi.string(native.table_about())..'\n'); return
        elseif (key=='--help' or key=='-h') and value==nil then output(1,help); return
        elseif key=='--plain' and value==nil then opts[#opts+1]=key
        elseif key=='--widths' or key=='--align' or key=='--overflow' or key=='--terminal-width' or key=='--color' or key=='--decimal-separator' then
            local v=val(); if key=='--color' then color=true; if v=='auto' then v=auto_color() and 'always' or 'never' end end; opts[#opts+1]=key; opts[#opts+1]=v
        else fail('unknown option: '..a) end
    end
    if not to then fail('--to is required') end; if not formats[to] then fail('output formats: csv, tsv, markdown, ir, ascii, ansi') end
    local auto=not from or from=='auto'; local s
    if auto then s=input(); from=detect(s,glyphs) end
    if not formats[from] then fail('input formats: auto, csv, tsv, markdown, ir, ascii, ansi') end
    if header_explicit and from~='csv' and from~='tsv' then fail('--header and --no-header apply only to CSV or TSV input') end
    local vis=to=='ascii' or to=='ansi'; local vin=from=='ascii' or from=='ansi'
    if vin and not allow then fail('visual input is lossy; pass --allow-lossy to accept padding removal and possible prior clipping') end
    if not vin and (allow or glyphs) then fail('--allow-lossy and --visual-glyphs require visual input') end
    if not vis and #opts>0 then fail('display options require ASCII or ANSI output') end
    if vis and not color then opts[#opts+1]='--color'; opts[#opts+1]=auto_color() and 'always' or 'never' end
    local explicit=false; for _,o in ipairs(opts) do if o=='--terminal-width' then explicit=true end end
    if vis and from~='tsv' and not explicit then
        local n=tonumber(native.table_env_columns()); if n==0 then n=tonumber(native.table_columns()) end; if n>0 then opts[#opts+1]='--terminal-width'; opts[#opts+1]=tostring(n) end
    end
    if from=='tsv' and vis and not auto then output(2,'table: visual output may clip, pad, or sanitize cell contents\n'); render(nil,true,to=='ascii',header,opts); return end
    s=s or input(); local t=parse(from,s,header,glyphs); local result
    if to=='ir' then result=ir_encode(t) elseif to=='markdown' then result=write_markdown(t)
    elseif to=='csv' or to=='tsv' then result=write_delimited(t,to=='csv')
    else output(2,'table: visual output may clip, pad, or sanitize cell contents\n'); result=render(write_delimited(t,false,true),false,to=='ascii',t.header,opts) end
    output(1,result)
end
local ok,err=pcall(run)
if not ok then output(2,'table: '..tostring(err)..'\n'); os.exit(1) end
