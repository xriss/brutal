--[[

First we must break a string into a table of brutal tokens

]]

-- start with C ish , might need to junk some of these
-- ideally most of this should just be left to right...
-- honestly I have never *trusted* this magical list...
local symbol_precedences={
	{
		"++",
		"--",
		".",
		"->",
	},
	{
		"+",
		"-",
		"!",
		"&",
	},
	{
		"*",
		"/",
		"%",
	},
	{
		"+",
		"-",
	},
	{
		"<<",
		">>",
	},
	{
		"<",
		"<=",
		">",
		">=",
		"==",
		"!=",
	},
	{
		"&",
		"^",
		"|",
	},
	{
		"&&",
		"^^",
		"||",
	},
	{
		"=",
		"+=",
		"-=",
		"*=",
		"/=",
		"%=",
		"<<=",
		">>=",
		"&=",
		"^=",
		"|=",
	},
	{
		",",
	},
}
local symbol_precedences_lookup={}
for level,list in ipairs(symbol_precedences) do
	for _,symbol in ipairs(list) do
		symbol_precedences_lookup[symbol]=leven
	end
end


local M={ modname=(...) } ; package.loaded[M.modname]=M
local trees=M

-- easy export
M.export=function(env,...)
	local tab={...}
	for i=1,#tab do tab[i]=env[ tab[i] ] end
	return unpack(tab)
end

trees.nodes={} -- node meta table
trees.nodes.__index=trees.nodes

trees.nodes.alloc = function(node)
	if not node then node={} end -- may pass in node
	setmetatable(node,trees.nodes) -- apply node meta table
	return node
end

trees.nodes.new = function(parent)
	local node=trees.nodes.alloc()
	node.tree=parent and parent.tree
	return node
end

trees.nodes.append = function(node,parent)
	node.parent=parent
	if parent then -- link child in array part of parent node
		parent[#parent+1]=node
	end
end

trees.nodes.bug = function(node,bug,context)
	return error(bug.." "..node.." "..context)
end

trees.nodes.dump = function(node,indent)
	if not indent then indent="" end
	print(indent..(node.is).." "..(#node).." "..(node.text or ""))
	for i,v in ipairs(node) do
		v:dump(indent.." ")
	end
end

trees.nodes.precedence = function(node)
	if node.is=="symbol" then
		return symbol_precedences_lookup[ node.symbol ] or 0
	end
	return 0
end

trees.nodes.parse_token = function(node,token)
	if token then
		node.token=token
	end
	local text=node.tree.code:sub( node.tree.tokens[node.token] , node.tree.tokens[node.token+1]-1 )

	local c =text:sub(1,1) -- one char test
	local cc=text:sub(1,2) -- two char test
	
	if c=="\"" or c=="'" or c=="`" then
		node.is="string"
		node.text=text
	elseif c==" " or c=="\t" or c=="\n" or c=="\r" then
		node.is="space"
		if text:find("\n") then
			node.space="line"
		end
	elseif c=="0" or c=="1" or c=="2" or c=="3" or c=="4" or c=="5" or c=="6" or c=="7" or c=="8" or c=="9" then
		node.is="number"
		node.text=text
		node.number=tonumber(text) -- todo: better number parser
	elseif cc=="//" or cc=="/*" then
		node.is="space"
		node.space="comment"
	elseif text=="(" or text=="{" or text=="[" then
		node.is="open"
		node.open=text
	elseif text==")" or text=="}" or text=="]" then
		node.is="close"
		node.close=text
	elseif text:find("^[a-zA-Z0-9_]+",1) then
		node.is="value"
		node.text=text
	else
		node.is="symbol"
		node.symbol=text
	end
end

trees.parse = function( code , tokens )

	local tree=trees.nodes.new()
	tree.is="tree"
	tree.tree=tree -- top tree
	tree.code=code
	tree.tokens=tokens
	
	local stack={}
	local pull=function() local node=stack[#stack] ; stack[#stack]=nil ; return node end
	local peek=function() return stack[#stack] end
	local push=function(node)
		local parent=peek()
		node:append(parent)
		stack[#stack+1]=node
	end
	local append=function(node)
		local parent=peek()
		node:append(parent)
	end
	
	push(tree)
	
	for idx=1,#tokens-1 do -- step through tokens
		local node=trees.nodes.new(tree)
		node:parse_token(idx)
		if node.is=="open" then
			push(node)
		elseif node.is=="close" then
			local t=pull()
			while t do
				if t.is=="open" then -- try match
					if t.open=="(" and node.close~=")" then return t:bug("(brackets)",node) end
					if t.open=="{" and node.close~="}" then return t:bug("{brackets}",node) end
					if t.open=="[" and node.close~="]" then return t:bug("[brackets]",node) end
					break
				end
				t=pull()
			end
			if not t then t:bug("brackets",node) end
			append(node)
		elseif node.is=="symbol" then
			local level=node:precedence()
			local test=peek():precedence()
			if level>test then
				push(node)
			else
				append(node)
			end
		else
			append(node)
		end
	end

	return tree
end
