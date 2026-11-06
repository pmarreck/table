-- Shared test/benchmark infrastructure. No conversion implementation is used.
local source=os.getenv('TABLE_PROFILING_SRC') or '@TABLE_PROFILING_SRC@'
assert(source:sub(1,1)=='/','TABLE_PROFILING_SRC must name the pinned profiling modules')
package.path=source..'/?.lua;'..package.path
local process=require('process')
local uv=require('luv')
local json=require('cjson')
local bit=require('bit')
local M={uv=uv,json=json}
function M.read(path)
    local file=assert(io.open(path,'rb')); local data=assert(file:read('*a')); assert(file:close()); return data
end
function M.run(binary,args,data,options)
    local argv={binary}; for _,value in ipairs(args or {}) do argv[#argv+1]=value end
    options=options or {}; options.stdin=data or ''; options.timeout_ms=options.timeout_ms or 15000
    local result=process.run(argv,options)
    assert(not result.timed_out,'command timed out: '..binary)
    return result
end
function M.checked(binary,args,data,options)
    local result=M.run(binary,args,data,options)
    assert(result.rc==0 and result.signal==0,binary..': '..result.stderr)
    return result.stdout
end
function M.sha256(binary)
    local tool=os.getenv('TABLE_SHA256') or '@TABLE_SHA256@'
    assert(tool:sub(1,1)=='/','TABLE_SHA256 must name the pinned hash tool')
    return assert(M.checked(tool,{binary}):match('^([a-f0-9]+)'))
end
function M.equal(a,b,message)
    assert(a==b,(message or 'values differ')..'\nexpected '..string.format('%q',b)..'\nactual '..string.format('%q',a))
end
function M.copy(value)
    if type(value)~='table' then return value end
    local out={}; for k,v in pairs(value) do out[k]=M.copy(v) end; return out
end
function M.csv(rows,newline)
    local out={}
    for _,row in ipairs(rows) do
        local fields={}
        for _,value in ipairs(row) do fields[#fields+1]=value:find('[,"\r\n]') and '"'..value:gsub('"','""')..'"' or value end
        out[#out+1]=table.concat(fields,',')..(newline or '\n')
    end
    return table.concat(out)
end
function M.fields(rows,record_markers)
    local out={}
    for _,row in ipairs(rows) do
        for _,field in ipairs(row) do out[#out+1]='F'..#field..':'..field end
        if record_markers then out[#out+1]='R' end
    end
    return table.concat(out)
end
function M.rng(seed)
    local state=bit.tobit(seed)
    return function(limit)
        state=bit.bxor(state,bit.lshift(state,13)); state=bit.bxor(state,bit.rshift(state,17)); state=bit.bxor(state,bit.lshift(state,5))
        local value=state<0 and state+4294967296 or state
        return value%limit
    end
end
function M.stream(binary)
    local stdin,stdout,stderr=uv.new_pipe(false),uv.new_pipe(false),uv.new_pipe(false)
    local timer=uv.new_timer(); local rc,signal,observed,timed_out,handle
    local chunks,errors={},{}
    local function finish()
        if rc~=nil and stdout:is_closing() and stderr:is_closing() and not timer:is_closing() then timer:stop(); timer:close() end
    end
    handle=assert(uv.spawn(binary,{args={'--from','tsv','--to','ascii','--widths','5,5','--color','never'},stdio={stdin,stdout,stderr}},function(code,sig)
        rc,signal=code,sig; handle:close(); finish()
    end))
    local function close_input() if not stdin:is_closing() then uv.shutdown(stdin,function() if not stdin:is_closing() then stdin:close() end end) end end
    uv.read_start(stdout,function(err,data)
        assert(not err,err)
        if data then
            chunks[#chunks+1]=data; local text=table.concat(chunks)
            for line in text:gmatch('[^\n]*\n') do
                if not observed and line:find('Alice',1,true) and line:find('12',1,true) then observed=true; close_input() end
            end
        else stdout:close(); close_input(); finish() end
    end)
    uv.read_start(stderr,function(err,data) assert(not err,err); if data then errors[#errors+1]=data else stderr:close(); finish() end end)
    assert(uv.write(stdin,'Name\tCount\nAlice\t12\n'))
    timer:start(10000,0,function()
        timed_out=true
        if not handle:is_closing() then handle:kill('sigkill') end
        close_input()
        if not stdout:is_closing() then stdout:close() end
        if not stderr:is_closing() then stderr:close() end
        timer:stop(); timer:close()
    end)
    uv.run()
    assert(observed and not timed_out and rc==0 and signal==0,'fixed-width output did not stream before EOF: '..table.concat(errors))
end
return M
