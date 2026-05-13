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

	elseif c=="0" or c=="1" or c=="2" or c=="3" or c=="4" or c=="5" or c=="6" or c=="7" or c=="8" or c=="9" or c=="." then -- number
	
		-- no leading 0 octal and numbers are doubles internally lua/js rules
		-- so everything is a double which means 48bit integers
		-- 64bit or 128bit ints are a problem for later... :)
		
		local cc=code:sub(idx,idx+1)
		
		if cc=="0x" or cc=="0X" then -- hex start

			local fs,fe = code:find("^[0-9a-fA-F]+",idx+2)
			if fe then
				return 1+fe-idx
			end
		
		elseif cc=="0b" or cc=="0B" then -- binary start
		
			local fs,fe = code:find("^[01]+",idx+2)
			if fe then
				return 1+fe-idx
			end

		end

		-- we need two patterns dealing with optional digits either side of decimal point
		-- we only allow 1 to 3 digits for exponent

		-- float with e number
		local fs,fe = code:find("^[0-9]*%.?[0-9]+[eE][%-]?[0-9][0-9]?[0-9]?",idx)	-- digits required after .
		if fe then return 1+fe-idx end
		local fs,fe = code:find("^[0-9]+%.?[0-9]*[eE][%-]?[0-9][0-9]?[0-9]?",idx)	-- digits required before .
		if fe then return 1+fe-idx end

		-- decimal or float without e number 
		local fs,fe = code:find("^[0-9]*%.?[0-9]+",idx)	-- digits required after .
		if fe then return 1+fe-idx end
		local fs,fe = code:find("^[0-9]+%.?[0-9]*",idx)	-- digits required before .
		if fe then return 1+fe-idx end
		
		-- it was just a . any number should have been caught above
		-- so fall through to final possible clumping of , s
		-- allowing numbers to start with a . or have a trailing . is possibly questionable
		-- it means we can not clump . but lets see how it goes
		-- we cant really concat strings without manageing memory anyhow
		-- so copying .. operator from lua is impossible
		-- maybe ... would be useful for variable args, unsure mostly I think easy numbers is more important
		-- I think if I push hard on tuples vargs might just sort of naturally happen
		-- anyway, later might drop the ability for numbers to start with a .

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
				-- which will turn into a comment when parsing
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
	-- note that brackets {} [] () and quotes ` ' " and . , ; \ do not clump
	-- white space or brackets *MUST* be used around clumping operators to prevent operator clumping
	-- this is mostly a problem for negative numbers
	-- EG to subtract a negative one it must be ( a- -1 ) or ( a-(-1) ) not ( a--1 )
	-- EG to assign a negative number it must be ( a= -1 ) or ( a=(-1)) not ( a=-1 )
	-- EG to raise number to a negative power it must be ( a^ -1 ) or ( a^(-1)) ) not ( a^-1 )

	local fs,fe = code:find("^[%~!@#%$%%%^&%*%+%-=|<>%?/:]+",idx) -- note the % escapes of magic chars
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
