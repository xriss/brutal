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

		local fs,fe=code:find("^[ \t\n\r]+",idx) -- clump all whitespace together
		return 1+fe-idx

	elseif c=="0" or c=="1" or c=="2" or c=="3" or c=="4" or c=="5" or c=="6" or c=="7" or c=="8" or c=="9" then -- number
	
		-- no leading 0 octal
		-- numbers are probably doubles internally lua/js rules
		-- 64bit or 128bit ints are a problem for later... :)
		
		-- I think we akso want C99 style hex floats with . and a pP exponent
		-- and allowing _ to break up constants so huge numbers can be easier to read
		-- this is very useful with large hex or binary constants
		
		-- since dot is a common operator, disallowing numbers that start with a . makes parsing more explicit
		-- same reasoning for why hex starts with an 0x

		local cc=code:sub(idx,idx+1)
		
		-- decimal 
		local digits="[0-9_]"
		local exponent="[eE]"
		local prefix=0
		
		if cc=="0x" or cc=="0X" then -- hex

			prefix=2
			digits="[0-9a-fA-F_]"
			exponent="[pP]"

		elseif cc=="0o" or cc=="0O" then -- octal

			prefix=2
			digits="[0-7_]"

		elseif cc=="0z" or cc=="0Z" then -- dozenal

			prefix=2
			digits="[0-9a-bA-B_]"

		elseif cc=="0b" or cc=="0B" then -- binary
		
			prefix=2
			digits="[0-1_]"

		elseif cc=="0d" or cc=="0D" then -- explicit decimal

			prefix=2

		end

		-- we need two patterns dealing with optional digits either side of decimal point

		-- decimal or float without e number
		local fs,fe = code:find("^"..digits.."+%.?"..digits.."*",idx+prefix)	-- digits required before .
		if fe then
			local ps,pe=code:find("^"..exponent.."[%-%+]?"..digits.."+",fe+1) -- check for e number
			if pe then return 1+pe-idx end
			return 1+fe-idx
		end
		
		-- decimal or float without e number
		local fs,fe = code:find("^"..digits.."*%.?"..digits.."+",idx+prefix)	-- digits required after .
		if fe then
			local ps,pe=code:find("^"..exponent.."[%-%+]?"..digits.."+",fe+1) -- check for e number
			if pe then return 1+pe-idx end
			return 1+fe-idx
		end

		-- a prefix with no digits might get here so just return that
		if prefix>0 then return prefix end

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

	elseif c:find("^[a-zA-Z0-9_]",1) then -- letter digit or _ 

		local fs,fe = code:find("^[a-zA-Z0-9_]+",idx) -- clump all letters and digits and _ together
		return 1+fe-idx

	else
	
		local cc=code:sub(idx,idx+1) -- two char test for // or /* comments
		if cc=="//" then -- single line comment

			if code:sub(idx+2,idx+2)=="`" then -- long string comment
				-- just skip the // and let the long string code handle the following long string
				-- later so a "//" followed by a long string can turn into a comment when parsing
				return 2
			end

			local fs,fe = code:find("\n",idx+2,true) -- end of line
			return 1+(fe or length)-idx
		
		elseif cc=="/*" then -- multi line comment

			local fs,fe = code:find("*/",idx+2,true) -- end of comment, no nesting
			return 1+(fe or length)-idx

		end

	end

	-- everything else is probably an operator so check for operator clumps
	-- note that brackets {} [] () and quotes ` ' " and , ; \ do not auto clump
	-- white space or brackets *MUST* be used around clumping operators to prevent operator clumping
	-- this is mostly a problem for negative numbers
	-- EG to subtract a negative one it must be ( a- -1 ) or ( a-(-1) ) not ( a--1 )
	-- EG to assign a negative number it must be ( a= -1 ) or ( a=(-1)) not ( a=-1 )
	-- EG to raise number to a negative power it must be ( a^ -1 ) or ( a^(-1)) ) not ( a^-1 )

	local fs,fe = code:find("^[%~!@#%$%%%^&%*%+%-=|<>%?/:%.]+",idx) -- note the % escapes of magic chars
	if fe then -- found a clump
		return 1+fe-idx
	end

	return 1
end

-- build array of strings for testing
tokens.code_to_tokens=function(code)
	local tokes={}
	
	local idx=1
	tokes[#tokes+1]=idx
	while true do		
		local len=tokens.next_token(code,idx)
		if not len then break end
		idx=idx+len
		tokes[#tokes+1]=idx
	end

	return tokes
end

-- build array of strings for testing
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
