--[[

genericish preprocessor that uses embedded lua (5.3) to handle includes and macros.

]]

local pplua={ modname=(...) } ; package.loaded[pplua.modname]=pplua

-- default brackets, chars may be repeated but close must match opening
-- eg <<[ ]>> or <[[ ]]>  could be used to "escape" the use of ]> within.
-- must be symbols and if a symbol is used twice it must close with the same character each time
pplua.brackets="<[]>"

local pp={} -- meta functions inherited from here
local meta={}
meta.__index=pp

pplua.create=function(pp)
	pp=pp or {}
	setmetatable(pp,meta)

	pp:set_brackets(pp.brackets or pplua.brackets)
	
	pp.env={}

	return pp
end

pp.set_brackets=function(pp,brackets)

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

pp.get_close_brackets=function(pp,bopen)
	local r=""
	for i=1,#bopen do
		r=pp.brackets_map[ bopen:sub(i,i) ]..r
	end
	return r
end

-- parse input into array of "text" and {"code"} segments using brackets
pp.split=function(pp,str)
	local aa={}
	
	local idx=1
	
	while idx <= #str do -- scan for brackets
	
		local s,e=str:find( pp.brackets_open_pat , idx )

		if s then -- found open so split

			local bopen=str:sub(s,e)
			local bclose=pp:get_close_brackets(bopen)

			aa[#aa+1]=str:sub(idx,s-1) -- text chunk
			idx=e+1

			local s,e=str:find( bclose , idx , true ) -- search for close
			
			if s then -- found close
				aa[#aa+1]={ code=str:sub(idx,s-1) } -- code chunk
				idx=e+1
			else -- close not found so use rest of string
				aa[#aa+1]={ code=str:sub(idx) } -- final code chunk
				idx=#str+1
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


pp.run=function(pp,list)

end

pp.join=function(pp,list)

end


do

local p=pplua.create()
p.list=p:split([=[

This is a test <<[ __LINE ]>> of how things split.

]=])

p:run()

print( p:join() )


end
