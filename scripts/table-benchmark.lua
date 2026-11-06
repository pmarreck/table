#!/usr/bin/env luajit
local here=arg[0]:match('^(.*)/[^/]+$') or '.'
package.path=here..'/table-support/?.lua;'..here..'/?.lua;'..package.path
local H=require('harness')
local B=require('benchmark')
if arg[1]=='--list' and #arg==1 then for _,case in ipairs(B.cases()) do print(case) end; return end
assert(#arg==3,'expected case, size and seed')
local implementation,rest=assert(arg[1]:match('^([^-]+)%-(.+)$'))
local workload,cores=assert(rest:match('^(.*)%-(%d+)$'))
local function contains(list,value) for _,v in ipairs(list) do if v==value then return true end end; return false end
assert(contains(B.implementations,implementation) and contains(B.workloads,workload) and (cores=='1' or cores=='12'))
local n=assert(tonumber(arg[2])); assert(n==(workload=='startup' and 1 or 4096))
local binary=assert(os.getenv('TABLE_BENCHMARK_'..implementation:upper()),'missing benchmark executable')
binary=assert(H.uv.fs_realpath(binary))
local digest,samples=B.measure(binary,workload,n)
print(H.json.encode({schema='performance-measurement/v1',correct=true,build_mode='release',implementation=implementation,
    binary_sha256=digest,adapter='LuaJIT + libuv',phase='fresh CLI launch through process exit and captured output; validation excluded',
    rows={{size=n,samples={wall_ns=samples}}}}))
