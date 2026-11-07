package.path='./scripts/?.lua;'..package.path
local H=require('harness')
local B=require('benchmark')
local binary,renderer,csv_oracle,markdown_cells=arg[1],arg[2],arg[3],arg[4]
assert(binary and renderer and csv_oracle and markdown_cells,'all test prerequisites are required')
local function run(args,data) return H.run(binary,args,data) end
local function convert(source,destination,data)
    local args={'--from',source,'--to',destination}
    if source=='ascii' or source=='ansi' then args[#args+1]='--allow-lossy' end
    if destination=='ascii' or destination=='ansi' then
        for _,v in ipairs({'--color','never','--terminal-width','80'}) do args[#args+1]=v end
    end
    return H.checked(binary,args,data)
end
local function success(result) assert(result.rc==0 and result.signal==0,result.stderr) end
local function failure(result) assert(result.rc~=0 and #result.stderr>0 and result.stdout=='','failure must be visible without partial stdout') end
local formats={'csv','tsv','markdown','ir','ascii','ansi'}
local source='name,value\n"A, B",12\nZ,3\n'
for _,from in ipairs(formats) do
    local data=convert('csv',from,source)
    for _,to in ipairs(formats) do H.equal(convert(to,'csv',convert(from,to,data)),source,from..' -> '..to) end
end
local wire_input='head,value\n"\27\28\29\30\31",\n'
local wire='\28T1\29head\31value\30\27e\27f\27g\27r\27u\31\30\28'
H.equal(convert('csv','ir',wire_input),wire)
H.equal(convert('ir','csv',wire),'head,value\n\27\28\29\30\31,\n')
local no_header=run({'--from','csv','--to','ir','--no-header'},'a,b\n')
success(no_header); H.equal(no_header.stdout,'\28T1a\31b\30\28')
local tsv='Name\tCount\nAlice\t12\nBob\t2\n'
local expected=H.checked(renderer,{'--ascii','--color','never','--terminal-width','80'},tsv)
local rendered=run({'--from','tsv','--to','ascii','--color','never','--terminal-width','80'},tsv)
success(rendered); H.equal(rendered.stdout,expected)
H.stream(binary)
-- Exhaust the ASCII cell domain: controls and delimiters must never use a
-- printable-ASCII shortcut. CSV quoting and trimmed spaces have fixed oracles.
for code=0,127 do
    local cell=string.char(code)
    local visual='+---+\n| '..cell..' |\n+---+\n'
    for _,format in ipairs({'ascii','ansi'}) do
        local result=run({'--from',format,'--to','csv','--allow-lossy'},visual)
        if code>=32 and code<=126 and cell~='|' then
            success(result)
            H.equal(result.stdout,H.csv({{cell==' ' and '' or cell}}),'ASCII visual cell '..code)
        else failure(result) end
    end
end
for _,test in ipairs({
    {{'--from','csv','--to','tsv'},'head\n"line\nline"\n'},
    {{'--from','csv','--to','csv'},'a,b\n1\n'},
    {{'--from','ascii','--to','csv'},'+---+\n| x |\n+---+\n'},
    {{'--from','ansi','--to','csv','--allow-lossy'},'\27]0;bad\7'},
}) do failure(run(test[1],test[2])) end
local sanitized=run({'--from','csv','--to','ansi','--color','never'},'name\n"evil\27[31m\nnext"\n')
success(sanitized); assert(not sanitized.stdout:find('\27',1,true) and sanitized.stdout:find('�',1,true))

-- Source detection: both spellings, all six formats, and explicit ambiguity.
source='name,value\nAlice,2\n'
for _,format in ipairs(formats) do
    local args={'--from','csv','--to',format}
    if format=='ascii' or format=='ansi' then
        for _,v in ipairs({'--terminal-width','80','--color',format=='ansi' and 'always' or 'never'}) do args[#args+1]=v end
    end
    local fixture=H.checked(binary,args,source)
    for _,auto in ipairs({false,true}) do
        local read_args=auto and {'--from','auto','--to','csv'} or {'--to','csv'}
        if format=='ascii' or format=='ansi' then read_args[#read_args+1]='--allow-lossy' end
        H.equal(H.checked(binary,read_args,fixture),source,'detection: '..format)
    end
end
for _,data in ipairs({'','name\nAlice\n','a,b\tc\n1,2\t3\n'}) do
    local r=run({'--to','csv'},data); failure(r); assert(r.stderr:find('--from',1,true))
end
for _,to in ipairs({'csv','tsv','ir'}) do failure(run({'--to',to},'a,b\tc\n1,2\t3\n')) end
H.equal(H.checked(binary,{'--from','tsv','--to','csv'},'a,b\tc\n1,2\t3\n'),'"a,b",c\n"1,2",3\n')
H.equal(H.checked(binary,{'--to','ir','--no-header'},'a,b\n'),'\28T1a\31b\30\28')
failure(run({'--to','csv'},'\28T1broken'))
failure(run({'--to','csv'},'\255,2\n'))
local plain=H.checked(binary,{'--from','csv','--to','ansi','--color','never'},source)
H.equal(H.checked(binary,{'--to','csv','--allow-lossy'},plain),source)
local denied=run({'--to','csv'},'+------+---+\n| name | n |\n+------+---+\n| A    | 2 |\n+------+---+\n')
failure(denied); assert(denied.stderr:find('--allow-lossy',1,true))

-- The independent csv crate reads every output field, including ASCII controls.
local rows={{'header','value','empty'}}
for code=0,127 do rows[#rows+1]={'ascii-'..code,string.char(code),''} end
local random=H.rng(20261105)
local alphabet={'a','b',',','"','\r','\n','\\','\t','界','é'}
for code=0,31 do alphabet[#alphabet+1]=string.char(code) end
for i=0,127 do
    local field={}; for _=1,random(25) do field[#field+1]=alphabet[1+random(#alphabet)] end
    rows[#rows+1]={'random-'..i,table.concat(field),''}
end
local encoded=H.csv(rows,'\r\n')
local expected_fields=H.fields(rows,true)
H.equal(H.checked(csv_oracle,{},encoded),expected_fields,'CSV oracle fixture')
local restored=convert('ir','csv',convert('csv','ir',encoded))
H.equal(H.checked(csv_oracle,{},restored),expected_fields,'CSV reference reader found changed fields')
H.equal(H.checked(csv_oracle,{},convert('csv','csv',encoded)),expected_fields)

-- GFM supplies the Markdown semantics; libxml2 extracts rendered cell text.
local values={}
for code=33,126 do local c=string.char(code); if not c:match('%w') then values[#values+1]=c end end
for _,v in ipairs({'\\|','\\\\|','&amp;','<b>x</b>','[x](https://example.test)','**strong**','`code`','界','é','👩‍💻'}) do values[#values+1]=v end
local markdown_rows={{'value'}}; for _,v in ipairs(values) do markdown_rows[#markdown_rows+1]={v} end
local markdown=convert('csv','markdown',H.csv(markdown_rows))
local html=H.checked('cmark-gfm',{'-e','table'},markdown)
H.equal(H.checked(markdown_cells,{},html),H.fields(markdown_rows,false),'GFM rendered cell contents changed')

-- The adapter/manifest registry must be complete, and wrong work must fail.
local manifest=H.json.decode(H.read('profiling.json'))
local expected_cases={}; for _,name in ipairs(B.cases()) do expected_cases[name]=true end
local count=0
for _,case in ipairs(manifest.cases) do if case.command[1]=='table-benchmark' then
    assert(expected_cases[case.name],'unknown/duplicate benchmark'); expected_cases[case.name]=nil; count=count+1
    assert(case.cores==tonumber(case.name:match('%-(%d+)$')))
    H.equal(H.json.encode(case.command),H.json.encode({'table-benchmark','{case}','{sizes}','{seed}'}))
end end
assert(count==#B.cases() and next(expected_cases)==nil,'missing benchmark case')
for _,workload in ipairs(B.workloads) do
    local digest,samples=B.measure(binary,workload,workload=='startup' and 1 or 4096)
    assert(#digest==64 and #samples==5); for _,sample in ipairs(samples) do assert(sample>0) end
end
local temporary=assert(H.uv.fs_mkdtemp(assert(os.getenv('TMPDIR'))..'/table-benchmark.XXXXXX'))
local wrong=temporary..'/wrong'
local file=assert(io.open(wrong,'wb')); assert(file:write('#!'..assert(os.getenv('TABLE_TEST_SHELL'))..'\nprintf "fabricated output\\n"\n')); assert(file:close()); assert(H.uv.fs_chmod(wrong,448))
local accepted=pcall(B.measure,wrong,'csv-tsv',4096)
assert(H.uv.fs_unlink(wrong)); assert(H.uv.fs_rmdir(temporary))
assert(not accepted,'benchmark accepted incorrect output')
print('Shared acceptance passed: '..binary)
