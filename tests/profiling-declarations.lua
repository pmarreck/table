package.path='./scripts/?.lua;'..package.path
local H=require('harness')
local B=require('benchmark')
local function validate(names,manifest)
    local expected,seen={},{}
    assert(#names>0,'no growth declarations')
    for _,name in ipairs(names) do
        assert(not seen[name],'duplicate adapter name'); seen[name]=true
        for _,cores in ipairs({1,12}) do expected[name..'-'..cores]=cores end
    end
    local actual={}; local count=0
    for _,case in ipairs(manifest.cases) do if case.mode=='cg' then
        assert(not actual[case.name],'duplicate growth case'); actual[case.name]=true; count=count+1
        assert(case.cores==expected[case.name],'wrong or missing case/cores: '..case.name)
        assert(case.metric=='wall_ns','wrong metric')
        H.equal(H.json.encode(case.command),H.json.encode({'table-perf','{case}','{sizes}','{seed}'}),'wrong command')
        local sizes=case.sizes; assert(#sizes>=3 and sizes[1]>0,'wrong sizes')
        for i=2,#sizes do assert(sizes[i]==2*sizes[i-1],'non-doubling sizes') end
        assert(#case.bounds==2 and case.bounds[1]>0 and case.bounds[2]>case.bounds[1],'wrong bounds')
    end end
    assert(count==#names*2,'missing growth case')
end
local function rejected(names,manifest) assert(not pcall(validate,names,manifest),'invalid declarations were accepted') end
local names={}; for line in H.checked(arg[1],{'--list'}):gmatch('[^\n]+') do names[#names+1]=line end
local manifest=H.json.decode(H.read('profiling.json'))
validate(names,manifest)
local index; for i,case in ipairs(manifest.cases) do if case.mode=='cg' then index=i; break end end
assert(index)
local missing=H.copy(manifest); table.remove(missing.cases,index); rejected(names,missing)
local duplicate=H.copy(manifest); duplicate.cases[#duplicate.cases+1]=H.copy(duplicate.cases[index]); rejected(names,duplicate)
local wrong=H.copy(manifest); wrong.cases[index].cores=99; rejected(names,wrong)
local undeclared=H.copy(names); undeclared[#undeclared+1]='undeclared-adapter'; rejected(undeclared,manifest)
-- Every declared adapter case must have exactly one manifest representation.
local memory_names=H.checked(arg[2],{'--list'})
local function all_modes(value)
    validate(names,value)
    local expected={}
    for _,name in ipairs(B.cases()) do
        expected[name]={mode='bm',command='table-benchmark',metric='wall_ns'}
    end
    for line in memory_names:gmatch('[^\n]+') do
        assert(not expected[line],'duplicate memory declaration')
        expected[line]={mode='mg',command='table-memory',metric=line=='csv-ir-memory' and 'peak_bytes' or 'allocation_count'}
    end
    for _,cores in ipairs({1,12}) do
        expected['startup-'..cores]={mode='bm',command='table-startup',metric='startup_ns'}
    end
    local seen={}
    for _,case in ipairs(value.cases) do
        assert(not seen[case.name],'duplicate case'); seen[case.name]=true
        if case.mode~='cg' then
            local declaration=assert(expected[case.name],'undeclared case: '..case.name)
            assert(case.mode==declaration.mode and case.metric==declaration.metric,'wrong case mode/metric')
            H.equal(H.json.encode(case.command),H.json.encode({declaration.command,'{case}','{sizes}','{seed}'}),'wrong command')
            assert(case.cores==(case.mode=='mg' and 1 or tonumber(case.name:match('%-(%d+)$'))),'wrong affinity')
            if case.mode=='mg' then
                assert(case.residual_allowance==0,'memory must retain no allocations')
                assert(#case.sizes==4 and case.sizes[1]==1024,'incomplete memory sweep')
                for i=2,#case.sizes do assert(case.sizes[i]==2*case.sizes[i-1],'memory sizes must double') end
                H.equal(H.json.encode(case.bounds),'[1.8,2.2]','wrong memory growth contract')
            end
        end
    end
    for name in pairs(expected) do assert(seen[name],'missing required case: '..name) end
end
all_modes(manifest)
local function rejects(value) assert(not pcall(all_modes,value),'invalid performance inventory accepted') end
for i,case in ipairs(manifest.cases) do
    if case.mode~='cg' then
        local absent=H.copy(manifest); table.remove(absent.cases,i); rejects(absent)
        local doubled=H.copy(manifest); doubled.cases[#doubled.cases+1]=H.copy(case); rejects(doubled)
        local malformed=H.copy(manifest); malformed.cases[i].command[1]='missing-adapter'; rejects(malformed)
        local bad_metric=H.copy(manifest); bad_metric.cases[i].metric='operations'; rejects(bad_metric)
    end
end
