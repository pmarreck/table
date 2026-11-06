package.path='./scripts/?.lua;'..package.path
local H=require('harness')
local diagnostic=arg[1]=='--pair'
local binaries={}; for i=diagnostic and 2 or 1,#arg do binaries[#binaries+1]=arg[i] end
assert(#binaries==(diagnostic and 2 or 4),'full qualification requires four CLIs; --pair is diagnostic only')
local env={COLUMNS='80',TERM='dumb',NO_COLOR='1',TSV_TO_ANSI_TABLE_GLYPHS=''}
local function run(binary,args,data) return H.run(binary,args,data,{env=env,timeout_ms=15000}) end
local count=0
local function compare(args,data)
    local expected=run(binaries[1],args,data)
    for i=2,#binaries do
        local actual=run(binaries[i],args,data)
        local description=binaries[i]..' '..table.concat(args,' ')..' input '..string.format('%q',data:sub(1,200))
        assert(actual.rc==expected.rc and actual.signal==expected.signal,description..': different exit status')
        H.equal(actual.stdout,expected.stdout,description..': stdout')
        H.equal(actual.stderr,expected.stderr,description..': stderr')
    end
    count=count+1
end
local formats={'csv','tsv','markdown','ir','ascii','ansi'}
local source='name,value\n界,é\nA,12\n'
for _,from in ipairs(formats) do
    local fixture=run(binaries[1],{'--from','csv','--to',from},source); assert(fixture.rc==0)
    for _,to in ipairs(formats) do
        local args={'--from',from,'--to',to}
        if from=='ascii' or from=='ansi' then args[#args+1]='--allow-lossy' end
        compare(args,fixture.stdout)
    end
    local args={'--to','csv'}; if from=='ascii' or from=='ansi' then args[#args+1]='--allow-lossy' end
    compare(args,fixture.stdout)
end
for _,args in ipairs({{},{'--help'},{'--wat'},{'--to'},{'--from'},{'--to','bad'},{'--to='},{'--to',''},
    {'--to=csv','--from=bad'},{'--to','csv','--color','never'},
    {'--from','csv','--to','csv','--allow-lossy'},
    {'--from','csv','--to','csv','--visual-glyphs','bad'}}) do compare(args,'') end
for _,from in ipairs(formats) do
    for _,data in ipairs({'','\n','a\tb\n1\n','a,b\n"unterminated','\255','\28T1\29\28','\28T1\27q\30\28','\28T1x\28','\27]0;bad\7','a\rb','h\n---\nx\n'}) do
        local args={'--from',from,'--to','csv'}; if from=='ascii' or from=='ansi' then args[#args+1]='--allow-lossy' end
        compare(args,data)
    end
    compare({'--from',from,'--to','csv','--no-header'},'')
end
local random=H.rng(20261106)
local alphabet={'a','b',',','"','\r','\n','\t','\\','|','界','é','\0','\27','\28','\29','\30','\31'}
for _=1,35 do
    local rows={{'h1','h2','h3'}}
    for _=1,3 do
        local row={}
        for _=1,3 do local field={}; for _=1,random(18) do field[#field+1]=alphabet[1+random(#alphabet)] end; row[#row+1]=table.concat(field) end
        rows[#rows+1]=row
    end
    local data=H.csv(rows,'\r\n')
    for _,to in ipairs({'csv','tsv','ir','markdown','ascii','ansi'}) do compare({'--from','csv','--to',to},data) end
end
for _,mode in ipairs({'never','always','auto'}) do
    for _,options in ipairs({{},{'--plain'},{'--widths','6,5'},{'--widths','4,5','--align','right,left'},{'--terminal-width','10'},{'--color','bad'},{'--overflow','bad'}}) do
        for _,test in ipairs({{'tsv','name\tvalue\nAlice\t12\n'},{'csv','name,value\nAlice,12\n'}}) do
            local args={'--from',test[1],'--to','ascii','--color',mode}; for _,v in ipairs(options) do args[#args+1]=v end
            compare(args,test[2])
        end
    end
end
for _,data in ipairs({'','a\n','a,b\tc\n1,2\t3\n','\28T1broken','\255'}) do compare({'--to','csv'},data) end
for _,data in ipairs({
    '+---+\n| | |\n+---+\n','+---+\n| x |\n+----+\n','+---+\n| 界 |\n+---+\n',
    '+---+\n| x |\n+---+\n| y |\n+---+\n| z |\n+---+\n',
    '\27]0;evil\7+---+\n| x |\n+---+\n','\27[2J+---+\n| x |\n+---+\n',
    '\27[31m+---+\27[0m\n| x |\n+---+\n','┌───┐───┐\n│ a │ b │\n└───┴───┘\n',
    '+---+\n| x |\n+---+\n\27[1A','┌──────┐\n│ 界 é │\n└──────┘\n','┌───┐\n│ \226\128\174x │\n└───┘\n',
}) do for _,from in ipairs({'ascii','ansi'}) do compare({'--from',from,'--to','csv','--allow-lossy'},data) end end
for _,test in ipairs({{'*~~~*\n! x !\n*~~~*\n','*,*,*,*,*,*,*,*,*,~,!'},
    {'╭───╮\n│ x │\n╰───╯\n','╭,┬,╮,├,┼,┤,╰,┴,╯,─,│'},
    {'A---C\n! x !\nG---I\n','A,B,C,D,E,F,G,H,I,-,!'}}) do
    compare({'--from','ansi','--to','csv','--allow-lossy','--visual-glyphs',test[2]},test[1])
end
for _,value in ipairs({' ',' ','\194\133',' ','‍','́','👩‍💻','🇺🇸','1️⃣','\226\128\168','\226\128\174'}) do
    local data=H.csv({{'h','value'},{'x',value}})
    for _,to in ipairs(formats) do compare({'--from','csv','--to',to},data) end
    for _,format in ipairs({'ascii','ansi'}) do
        local rendered=run(binaries[1],{'--from','csv','--to',format},data); assert(rendered.rc==0)
        compare({'--from',format,'--to','csv','--allow-lossy'},rendered.stdout)
    end
end
for _,binary in ipairs(binaries) do
    local about=run(binary,{'--about'},'')
    assert(about.rc==0 and about.stderr=='' and about.stdout:find('PF=',1,true) and about.stdout:match('^[^\n]+\n$'))
end
assert(count==496,'parity corpus lost cases')
print((diagnostic and 'Diagnostic' or 'Full')..' parity: '..count..' cases agree across '..#binaries..' CLIs')
