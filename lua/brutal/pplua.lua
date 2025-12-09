--[[

genericish preprocessor that uses embedded lua (5.3) to handle includes and macros.

]]

local M={ modname=(...) } ; package.loaded[M.modname]=M

-- easy export
M.export=function(env,...)
	local tab={...}
	for i=1,#tab do tab[i]=env[ tab[i] ] end
	return unpack(tab)
end

local pplua={} -- pplua meta functions inherited from here
pplua.__index=pplua -- self index
M.pplua=pplua -- expose

M.create=function(pp)
	pp=pp or {}
	setmetatable(pp,M.pplua)

-- default brackets, chars may be repeated but close must match opening
-- eg <<[ ]>> or <[[ ]]>  could be used to "escape" the use of ]> within.
-- must be symbols and if an open symbol is repeated it must close with the same symbol each time
	pp:set_brackets(pp.brackets or "<[]>")
	
	pp.flags=pp.flags or {}

	-- merge default flags
	local flags={
		needclose=true,				-- require closing brackets
		ignoreshebang=true,			-- replace first line with \n if it begins with #!
	}
	for n,v in pairs(flags) do
		if type(pp.flags[n])=="nil" then
			pp.flags[n]=v
		end
	end
	
	pp.env=pp:get_env()

	pp.list={}

	return pp
end

-- set brackets string and cache versions/parts of it
pplua.get_env=function(pp)

local env={
	assert=assert,
	error=error,
	ipairs=ipairs,
	pairs=pairs,
	next=next,
	pcall=pcall,
	select=select,
	tonumber=tonumber,
	tostring=tostring,
	type=type,
	unpack=unpack,
	xpcall=xpcall,
	_VERSION=_VERSION,
	coroutine={
		create=coroutine and coroutine.create,
		resume=coroutine and coroutine.resume,
		running=coroutine and coroutine.running,
		status=coroutine and coroutine.status,
		wrap=coroutine and coroutine.wrap,
		yield=coroutine and coroutine.yield,
	},
	table={
		concat=table and table.concat,
		insert=table and table.insert,
		maxn=table and table.maxn,
		remove=table and table.remove,
		sort=table and table.sort,
	},
	string={
		byte=string and string.byte,
		char=string and string.char,
		find=string and string.find,
		format=string and string.format,
		gmatch=string and string.gmatch,
		gsub=string and string.gsub,
		len=string and string.len,
		lower=string and string.lower,
		match=string and string.match,
		rep=string and string.rep,
		reverse=string and string.reverse,
		sub=string and string.sub,
		upper=string and string.upper,
	},
	math={
		abs=math and math.abs,
		acos=math and math.acos,
		asin=math and math.asin,
		atan=math and math.atan,
		atan2=math and math.atan2,
		ceil=math and math.ceil,
		cos=math and math.cos,
		cosh=math and math.cosh,
		deg=math and math.deg,
		exp=math and math.exp,
		floor=math and math.floor,
		fmod=math and math.fmod,
		frexp=math and math.frexp,
		huge=math and math.huge,
		ldexp=math and math.ldexp,
		log=math and math.log,
		log10=math and math.log10,
		max=math and math.max,
		min=math and math.min,
		modf=math and math.modf,
		pi=math and math.pi,
		pow=math and math.pow,
		rad=math and math.rad,
		random=math and math.random, -- should replace with sandboxed versions
		randomseed=math and math.randomseed, -- should replace with sandboxed versions
		sin=math and math.sin,
		sinh=math and math.sinh,
		sqrt=math and math.sqrt,
		tan=math and math.tan,
		tanh=math and math.tanh,
	},
	os={
		clock=os and os.clock,
		date=os and os.date, -- this can go boom in some situations?
		difftime=os and os.difftime,
		time=os and os.time,
	},
}
	
	return env
end

-- set brackets string and cache versions/parts of it
pplua.set_brackets=function(pp,brackets)

	pp.brackets=brackets
	
	pp.brackets_len=math.floor( (#pp.brackets)/2 )
	pp.brackets_open=pp.brackets:sub(1,pp.brackets_len)
	pp.brackets_close=pp.brackets:sub(-pp.brackets_len)
	
	pp.brackets_open_pat =pp.brackets_open:gsub( ".",function(a) return "%"..a.."+" end )
	pp.brackets_close_pat=pp.brackets_close:gsub(".",function(a) return "%"..a.."+" end )
	pp.brackets_map={}
	for i=1,pp.brackets_len do
		pp.brackets_map[ pp.brackets_open:sub(i,i) ] = pp.brackets_close:sub(-i,-i)
	end

	print( pp.brackets_open_pat )
	print( pp.brackets_close_pat )

end

-- given an open brackets string work out the reversed closing one
pplua.get_close_brackets=function(pp,bopen)
	local r=""
	for i=1,#bopen do
		r=pp.brackets_map[ bopen:sub(i,i) ]..r
	end
	return r
end

-- split input text into array of "text" and {code="text"} segments using simple brackets
pplua.split=function(pp,str)
	local aa={}
	
	local idx=1
	
	if pp.flags.ignoreshebang then
		if str:sub(1,2)=="#!" then -- found a https://en.wikipedia.org/wiki/Shebang_(Unix) 
			local s,e=str:find( "\n" , idx , true ) -- so we will ignore the entire first line
			if not e then e=#str end -- in case there is only one line with no \n
			aa[#aa+1]={ "\n" , idx=e+1,  shebang=str:sub(1,e) } -- replace first line with an empty line 
			idx=e+1
		end
	end
	
	while idx <= #str do -- scan for brackets
	
		local s,e=str:find( pp.brackets_open_pat , idx )

		if s then -- found open so split

			local bopen=str:sub(s,e)
			local bclose=pp:get_close_brackets(bopen)

			aa[#aa+1]=str:sub(idx,s-1) -- text chunk
			idx=e+1

			local s,e=str:find( bclose , idx , true ) -- search for close
			
			if e then -- found close
			
				aa[#aa+1]={ idx=e+1, code=str:sub(idx,s-1), bopen=bopen, bclose=bclose, } -- code chunk
				idx=e+1
				
			else -- close not found so use rest of string or error
				
				if pp.flags.needclose then
					error("missing close brackets "..bclose ) -- TODO: error line etc
				else
					e=#str
					aa[#aa+1]={ idx=e+1, code=str:sub(idx), bopen=bopen } -- final code chunk
					idx=e+1
				end
			end

		else -- open not found advance to end of string

			aa[#aa+1]=str:sub(idx) -- final text chunk
			idx=#str+1

		end
	
	end

print("dump")
for i,v in ipairs(aa) do print(i,v) end

	return aa
end


pplua.join=function(pp,list)

	local out={}

	list=list or pp.list
	
	for i,v in ipairs(list) do -- concat all array slots
	
		if type(v)=="table" then -- sub table
			out[#out+1]=pp:join(v)
		elseif v then -- ignore false which can be used for place holders
			out[#out+1]=tostring(v)
		end

	end
	
	return table.concat(out,"")

end

pplua.run=function(pp,list)

	list=list or pp.list

	for i,v in ipairs(list) do -- run all array slots	
		if type(v)=="table" then
			if v.code then -- we have some code to run
				pp:run_lua(v)			
			end
			pp:run(v) -- run may have generated some sub code eg by require so iterate output
		end
	end

end

pplua.run_lua=function(pp,it)

	-- remove output before we run
	for i=#it,1,-1 do
		it[i]=nil --remove
	end

	local f,err
	
	f,err=load("local _pp,_it=...;return\n"..it.code,"pp","t",pp.env) -- try with return prefix for simple variable insertion
	if not f then
		f,err=load("local _pp,_it=...;\n"..it.code,"pp","t",pp.env) -- if that failed then try without return prefix
	end
	if not f then
		error(err) -- TODO: better error line etc
	end
	
	local r={ f(pp,it) } -- run the lua code inside pp.env and capture all output
	-- the function may have inserted some values so append any return values
	for i,v in ipairs(r) do
		if v then -- must be true
			it[#it+1]=v
		end
	end
	
end


do

local pp=M.create()
pp.list=pp:split([===[#! ignore me
<[

-- simple test macro, must be global
test=function(a)

	return a*111

end

]>
This is a test <<[ test(_it.idx) , "ok" , false , true   ]>> of how things split.

]===])

pp:run()

print( pp:join() )


end
