local H=require('harness')
local M={implementations={'rust','zig','roc','luajit'},workloads={'startup','csv-tsv','csv-ir','markdown-csv','ascii-csv','autodetect-csv'}}
function M.fixture(workload,n)
    local csv='name,count\n'..string.rep('alpha,42\n',n)
    if workload=='startup' or workload=='csv-tsv' then return {'--from','csv','--to','tsv'},csv,'name\tcount\n'..string.rep('alpha\t42\n',n) end
    if workload=='csv-ir' then return {'--from','csv','--to','ir'},csv,'\28T1\29name\31count\30'..string.rep('alpha\31'..'42\30',n)..'\28' end
    if workload=='markdown-csv' then return {'--from','markdown','--to','csv'},'| name | count |\n| --- | --- |\n'..string.rep('| alpha | 42 |\n',n),csv end
    if workload=='ascii-csv' then return {'--from','ascii','--to','csv','--allow-lossy'},'+-------+-------+\n| name  | count |\n+-------+-------+\n'..string.rep('| alpha | 42    |\n',n)..'+-------+-------+\n',csv end
    if workload=='autodetect-csv' then return {'--to','csv'},csv,csv end
    error('unknown workload: '..workload)
end
function M.cases()
    local result={}
    for _,implementation in ipairs(M.implementations) do
        for _,workload in ipairs(M.workloads) do
            for _,cores in ipairs({1,12}) do result[#result+1]=implementation..'-'..workload..'-'..cores end
        end
    end
    return result
end
function M.measure(binary,workload,n)
    local args,data,expected=M.fixture(workload,n)
    local digest=H.sha256(binary)
    -- Settle the adapter before each fresh child; child startup stays timed.
    local warm=H.run(binary,args,data,{timeout_ms=30000})
    assert(warm.rc==0 and warm.signal==0,'benchmark warmup failed: '..warm.stderr)
    H.equal(warm.stdout,expected,'incorrect benchmark warmup output')
    local samples={}
    for _=1,5 do
        collectgarbage('collect')
        collectgarbage('collect')
        local start=H.uv.hrtime()
        local result=H.run(binary,args,data,{timeout_ms=30000})
        local elapsed=tonumber(H.uv.hrtime()-start)
        assert(result.rc==0 and result.signal==0,'incorrect '..workload..' conversion: '..result.stderr)
        H.equal(result.stdout,expected,'incorrect '..workload..' output')
        H.equal(H.sha256(binary),digest,'benchmark executable changed during measurement')
        samples[#samples+1]=elapsed
    end
    return digest,samples
end
return M
