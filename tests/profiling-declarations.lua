package.path='./scripts/?.lua;'..package.path
local H=require('harness')
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
