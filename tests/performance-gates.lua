-- Bounded deterministic resource checks, not historical performance approval.
package.path='./scripts/?.lua;'..package.path
local H=require('harness')
local core=require('core') -- Independently maintained, pinned profiling policy.
local config=require('config')
local manifest=config.validate(H.json.decode(H.read('profiling.json')))
local memory=assert(arg[1],'memory probe required')
local cases={}
for _,case in ipairs(manifest.cases) do
    if case.mode=='mg' then cases[#cases+1]=case end
end
assert(#cases==2,'both memory metrics are required')
local function evaluate(case,measurement)
    return core.evaluate(case,measurement,{count=0})
end
local function rejected(case,measurement,verdict)
    local result=evaluate(case,measurement)
    assert(result.verdict==verdict and not result.retryable,
        'negative control: expected '..verdict..', got '..result.verdict)
end
for _,case in ipairs(cases) do
    local sizes={}; for _,n in ipairs(case.sizes) do sizes[#sizes+1]=tostring(n) end
    local measurement=H.json.decode(H.checked(memory,{case.name,table.concat(sizes,','),'20261120'}))
    local result=evaluate(case,measurement)
    assert(result.verdict=='UNBASELINED',case.name..': deterministic resource limits failed: '..result.verdict)
    -- Preserve the external engine's distinction: bounds hold, history unapproved.
    assert(result.approvable and #result.ratios==#case.sizes-1)
    local wrong=H.copy(measurement); wrong.correct=false; rejected(case,wrong,'INVALID')
    local missing=H.copy(measurement); table.remove(missing.rows); rejected(case,missing,'INVALID')
    local leak=H.copy(measurement); leak.rows[1].residual_bytes[2]=1; rejected(case,leak,'LEAK')
    local zero=H.copy(measurement); zero.rows[1].samples[case.metric][2]=0; rejected(case,zero,'INVALID')
    for _,shape in ipairs({'quadratic','crossover','constant'}) do
        local bad=H.copy(measurement)
        for i,row in ipairs(bad.rows) do
            local value=shape=='constant' and 100 or row.size
            if shape=='quadratic' or (shape=='crossover' and i==#bad.rows) then value=row.size^2 end
            row.samples[case.metric]={value,value,value}
        end
        rejected(case,bad,'SHAPE_FAIL')
    end
end
print('deterministic allocation growth and cleanup limits hold; historical baselines remain separate')
