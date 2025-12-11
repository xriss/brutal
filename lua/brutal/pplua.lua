--[[

genericish preprocessor that uses embedded lua (5.3) to handle includes and macros.

]]

local wpath=require("wetgenes.path") -- this will use lfs_any so overload that for a custom filesystem

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

-- keep this function out of the parse code for sanity/security so chunk code cannot change the search paths.
local get_load_file=function(pp,_paths)

	local loaded={}
	local paths={false} -- reserve first slot for current files directory
	
	for i,v in ipairs(_paths) do 
		paths[#paths+1]=wpath.resolve(v)
	end

	local valid_path=function(p)
		for i,path in ipairs(paths) do
			if path then
				-- must begin with one of these paths
				if p:sub(1,#path)==path then return true end
			end
		end
		return false -- out of scope
	end

	local load_file=function(pp,filename)

		for i,path in ipairs(paths) do
			if path then
				local p=wpath.resolve(path,filename) -- filename can contain .. etc
				if valid_path(p) then -- but must stay within valid registered search paths
					if loaded[p] then -- cache
						return p,loaded[p]
					else
						local fp=io.open(p,"rb")
						if fp then
							local data=fp:read("*all")
							fp:close()
							return p,data
						end
					end
				end
			end
		end

		return nil,nil -- fail
	end

	return load_file
end

-- create must provide search paths this can not be changed later
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
	
	pp.search=pp.search or {"."} -- search paths, note this can not be changed while parsing and must be given here
	pp.load_file=get_load_file(pp,pp.search)
	pp.required={} -- map of previously required files
	
	pp.env=pp:get_env()

	pp.root=nil
	
	pp.chunkidx=1

	return pp
end

-- so we can fill a chunk up with current parse info etc
pplua.create_chunk=function(pp,chunk)
	
	chunk=chunk or {}
	
	chunk.idx=pp.chunkidx
	pp.chunkidx=pp.chunkidx+1

	return chunk
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
	coroutine=coroutine and {
		create=coroutine.create,
		resume=coroutine.resume,
		running=coroutine.running,
		status=coroutine.status,
		wrap=coroutine.wrap,
		yield=coroutine.yield,
	},
	table=table and {
		concat=table.concat,
		insert=table.insert,
		maxn=table.maxn,
		remove=table.remove,
		sort=table.sort,
	},
	string=string and {
		byte=string.byte,
		char=string.char,
		find=string.find,
		format=string.format,
		gmatch=string.gmatch,
		gsub=string.gsub,
		len=string.len,
		lower=string.lower,
		match=string.match,
		rep=string.rep,
		reverse=string.reverse,
		sub=string.sub,
		upper=string.upper,
	},
	math=math and {
		abs=math.abs,
		acos=math.acos,
		asin=math.asin,
		atan=math.atan,
		atan2=math.atan2,
		ceil=math.ceil,
		cos=math.cos,
		cosh=math.cosh,
		deg=math.deg,
		exp=math.exp,
		floor=math.floor,
		fmod=math.fmod,
		frexp=math.frexp,
		huge=math.huge,
		ldexp=math.ldexp,
		log=math.log,
		log10=math.log10,
		max=math.max,
		min=math.min,
		modf=math.modf,
		pi=math.pi,
		pow=math.pow,
		rad=math.rad,
		random=math.random, -- should replace with sandboxed versions
		randomseed=math.randomseed, -- should replace with sandboxed versions
		sin=math.sin,
		sinh=math.sinh,
		sqrt=math.sqrt,
		tan=math.tan,
		tanh=math.tanh,
	},
	os=os and {
		clock=os.clock,
		date=os.date, -- this can go boom in some situations?
		difftime=os.difftime,
		time=os.time,
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

end

-- given an open brackets string work out the reversed closing one
pplua.get_close_brackets=function(pp,bopen)
	local r=""
	for i=1,#bopen do
		r=pp.brackets_map[ bopen:sub(i,i) ]..r
	end
	return r
end

-- split input text into array of "text" and {code="text"} chunks separated using simple brackets
pplua.split=function(pp,str)

	local chunk=pp:create_chunk()
	local push=function(v) chunk[#chunk+1]=v end
	
	local idx=1
	
	if pp.flags.ignoreshebang then
		if str:sub(1,2)=="#!" then -- found a https://en.wikipedia.org/wiki/Shebang_(Unix) 
			local s,e=str:find( "\n" , idx , true ) -- so we will ignore the entire first line
			if not e then e=#str end -- in case there is only one line with no \n
			push(pp:create_chunk({ "\n" , shebang=str:sub(1,e) })) -- replace first line with an empty line 
			idx=e+1
		end
	end
	
	while idx <= #str do -- scan for brackets
	
		local s,e=str:find( pp.brackets_open_pat , idx )

		if s then -- found open so split

			local bopen=str:sub(s,e)
			local bclose=pp:get_close_brackets(bopen)

			push(str:sub(idx,s-1)) -- text chunk
			idx=e+1

			local s,e=str:find( bclose , idx , true ) -- search for close
			
			if e then -- found close
			
				push(pp:create_chunk({ code=str:sub(idx,s-1), bopen=bopen, bclose=bclose, })) -- code chunk
				idx=e+1
				
			else -- close not found so use rest of string or error
				
				if pp.flags.needclose then
					error("missing close brackets "..bclose ) -- TODO: error line etc
				else
					e=#str
					push(pp:create_chunk({ code=str:sub(idx), bopen=bopen })) -- final code chunk
					idx=e+1
				end
			end

		else -- open not found advance to end of string

			push(str:sub(idx)) -- final text chunk
			idx=#str+1

		end
	
	end

	return chunk
end

-- join processed chunks back together
pplua.join=function(pp,chunk)

	local map={} -- todo generate source map
	local out={}
	
	for i,v in ipairs(chunk) do -- concat all array slots
	
		if type(v)=="table" then -- sub table
			out[#out+1]=pp:join(v)
		elseif v then -- ignore false which can be used for place holders
			out[#out+1]=tostring(v)
		end

	end
	
	return table.concat(out,""),map

end

-- process chunks
pplua.run=function(pp,chunk)

	for i,v in ipairs(chunk) do -- run all array slots	
		if type(v)=="table" then
			if v.code then -- we have some code to run
				pp:run_lua(v)			
			end
			pp:run(v) -- run may have generated some sub code eg by require so iterate output
		end
	end

end

-- exposed locals available at parse time, pp and ppchunk are passed in via ...
local ppvars="local pp,ppchunk=...;"..
"local ppinclude=function(name) return pp:include(ppchunk,name) end;"..
"local pprequire=function(name) return pp:require(ppchunk,name) end;"..
"local ppinsert =function(text) return pp:insert(ppchunk,text)  end;"..
"local pptext   =function(text) return pp:out(ppchunk,text)     end;"
-- these are all on one line so we only add one line to the chunk code

-- process a chunk as lua
pplua.run_lua=function(pp,chunk)

	-- remove output before we run
	for i=#chunk,1,-1 do
		chunk[i]=nil --remove
	end

	local f,err
	
	f,err=load(ppvars.."return\n"..chunk.code,"ppchunk"..(chunk.idx),"t",pp.env) -- try with return prefix for simple variable insertion
	if not f then
		f,err=load(ppvars.."\n"..chunk.code,"ppchunk"..(chunk.idx),"t",pp.env) -- if that failed then try without return prefix
	end
	if not f then
		error(err) -- TODO: better error line etc
	end
	
	local r={ f(pp,chunk) } -- run the lua code inside pp.env and capture all output
	-- the function may have inserted some values so append any return values
	for i,v in ipairs(r) do
		if v then -- must be true
			chunk[#chunk+1]=v
		end
	end
	
end


-- include a file into this chunk
pplua.include=function(pp,chunk,name)
	local path,text=pp:load_file(name)
	if not path then error("include file not found "..name) end
	pp:insert(chunk,text)
end

-- include a file into this chunk once
-- so only include if not required before ( may have been included before )
pplua.require=function(pp,chunk,name)
	local path,text=pp:load_file(name)
	if not path then error("require file not found "..name) end
	if not pp.required[path] then -- first time
		pp.required[path]=text -- remember
		pp:insert(chunk,text)
	end
	-- do nothing if already required
end

-- include split text in chunk output ( so it may contain more bracketed values )
pplua.insert=function(pp,chunk,text)
	chunk[#chunk+1]=pp:split(text)
end

-- include text in chunk output as an alternative to a chunk returning values
pplua.out=function(pp,chunk,text)
	chunk[#chunk+1]=text
end
