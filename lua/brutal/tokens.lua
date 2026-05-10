--[[

First we must break a string into a table of brutal tokens

]]

local M={ modname=(...) } ; package.loaded[M.modname]=M
local tokens=M

-- easy export
M.export=function(env,...)
	local tab={...}
	for i=1,#tab do tab[i]=env[ tab[i] ] end
	return unpack(tab)
end

-- code is the input code string and idx is the current parsing point
-- returns length of next token from this point or nil if no more tokens
tokens.next_token=function(code,idx)
	local length=#code
	if idx>length then return end

	local c=code:sub(idx,idx) -- first char, this will decide the type
	if c==" " or c=="\t" or c=="\n" or c=="\r" then -- white space

		local fs,fe=code:find("^%s+",idx) -- clump all whitespace together
		return 1+fe-idx
		
	elseif c=="\"" or c=="'" then -- simple " or ' string with possible \ escapes

		local quote=c
		local look=idx+1
		while true do
			local fs,fe = code:find("["..quote.."\\]",look) -- need to handle basic escapes
			if not fs then -- no terminator, rest of code is all one token ( error later )
				return 1+length-idx
			end
			c=code:sub(fs,fs)
			if c==quote then -- found terminator
				return 1+fs-idx
			elseif c=="\"" then -- skip next char and continue looking for terminator
				look=fs+2
			end
		end

	elseif c=="`" then -- ` string, no escapes, may contain binary values

		local quote=c -- might just be a single ` or a long quote
		local fs,fe = code:find("^`['\"]+`",look) -- a long quote is two backticks with a combination of ' or " inside them
		if fs then
			quote=code:sub(fs,fe)
		end
		local fs,fe = code:find(quote,look+#quote,true) -- string may contain anything ( even \0 ) *except* the quote
		return 1+(fe or length)-idx

	elseif c:find("[%w_]",1) then -- letter digit or _ 

		local fs,fe = code:find("^[%w_]+",idx) -- clump all letters and digits and _ together
		return 1+fe-idx

	else
	
		local cc=code:sub(idx,idx+1) -- two char test for // or /* comments
		if cc=="//" then -- single line comment

			if code:sub(idx+2,idx+2)=="`" then -- long string comment
				-- just skip the // and let the long string code handle the following long string
				return 2
			end

			local fs,fe = code:find("\n",idx+2,true) -- end of line
			return 1+(fe or length)-idx
		
		elseif cc=="/*" then -- multi line comment

			local fs,fe = code:find("*/",idx+2,true) -- end of comment, no nesting
			return 1+(fe or length)-idx

		end

	end

	-- everything else is a single character symbol or control code
	-- we can join them together later for operators like ++ -- etc etc

	return 1
end


tokens.code_to_strings=function(code)
	local strings={}
	
	local idx=1
	while true do
		
		local len=tokens.next_token(code,idx)
		if not len then break end

		local s=code:sub(idx,idx+len-1)
		strings[#strings+1]=s
		idx=idx+len
	end

	return strings
end
