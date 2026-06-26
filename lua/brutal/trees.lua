--[[

First we must break a string into a table of brutal tokens

]]

-- precedence is tight , loose or none
local operators_list={
	-- tight operators grab the closest left/right values
	tight={
		"*",
		"/",
		"%",
		".",
		"->",
	},
	-- loose operators grab everything to the left/right *except* other loose operators
	loose={
		-- tuples
		",",
		-- assignment
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
		-- equality
		"<",
		"<=",
		">",
		">=",
		"==",
		"!=",
		"~=",
	},
	-- everything else is none and will be left to right
}
local operators_map={}
for name,tab in pairs(operators_list) do
	for _,opp in pairs(tab) do
		operators_map[opp]=name
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

trees.nodes.new_list = function(node,parent)
	node=trees.nodes.alloc(node)
	node.is="list"
	node.list={}
	if parent then
		trees.nodes.append(node,parent)
	end
	return node
end

trees.nodes.loose_list = function(parent,symbol)
	local node=trees.nodes.new_list()
	node.greed="loose"
	
	while parent.greed do parent=parent.parent end -- go up until out of greed

	if symbol then symbol:append(parent) end -- insert symbol if exists

	node:append(parent) -- then new list

	return node
end

-- get the last node from this parents list
trees.nodes.peek = function(node)
	return node.list[#node.list]
end

-- remove the last node from this parents list
trees.nodes.pop = function(node)
	local left=node.list[#node.list]
	node.list[#node.list]=nil
	return left
end

trees.nodes.append = function(node,parent)
	node.parent=parent
	if parent then -- link child in array part of parent list node
		assert(parent.is=="list")
		node.root=parent.root
		parent.list[#parent.list+1]=node
	end
end

trees.nodes.bug = function(node,bug,context)
	if node.root then node.root:dump() end
	return error(bug.." "..tostring(node).." "..tostring(context))
end

trees.nodes.dumplist = function(node)
	for i,v in ipairs(node.list) do
		print(node.is,node.list and #node.list or "nil")
	end
end
trees.nodes.dump = function(node,indent)
	if not indent then indent="" end
	if node.is=="list" then
--		print(indent..(node.is).." "..(#node.list).." "..(node.greed or ""))
		for i,v in ipairs(node.list) do
			v:dump(indent.." ")
		end
	else
		print(indent..(node.is).." "..(node.text or ""))
	end
end

trees.nodes.symbol_greed = function(node)
	if node.is=="symbol" then
		return operators_map[node.text] or "none"
	end
	return nil
end

trees.nodes.match_bracket = function(parent,bracket)
	local ob
	if bracket==")" then ob="(" end
	if bracket=="}" then ob="{" end
	if bracket=="]" then ob="[" end
	assert(ob)
	while parent do -- search up matching open bracket which will be at start of a list
		if parent.list[1].open==ob then
			return parent
		end
		parent=parent.parent
	end
end

trees.nodes.parse_token = function(node,token)
	if token then
		node.token=token
	end
	local text=node.root.code:sub( node.root.tokens[node.token] , node.root.tokens[node.token+1]-1 )

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
		node.text=text
		node.space="comment"
	elseif text=="(" or text=="{" or text=="[" then
		node.is="open"
		node.text=text
		node.open=text
	elseif text==")" or text=="}" or text=="]" then
		node.is="close"
		node.text=text
		node.close=text
	elseif text:find("^[a-zA-Z0-9_]+",1) then
		node.is="value"
		node.text=text
	else
		node.is="symbol"
		node.text=text
	end
	return node
end

trees.parse = function( code , tokens )

	local root=trees.nodes.new_list()
	root.root=root -- top tree is the root
	root.code=code
	root.tokens=tokens

	local parent=root:loose_list() -- start a loose list
	for idx=1,#tokens-1 do -- step through tokens
		local node=trees.nodes.alloc({root=root}):parse_token(idx)
		if node.is=="open" then
			parent=trees.nodes.new_list(nil,parent) -- push
			node:append(parent)
			parent=parent:loose_list() -- this *may* be a tuple so start loose
		elseif node.is=="close" then
			local match=parent:match_bracket(node.close)
			if not match then -- did not find matching bracket
				return parent:bug("(brackets)",node)
			end
			parent=match
			node:append(parent)
			parent=parent.parent -- pop
		elseif node.is=="value" then

			local left=parent:peek()
			if left and ( left.is=="value" or left.is=="number" or left.is=="list" ) then
				-- auto statement separator
				parent=parent:loose_list()
			end
			node:append(parent)

		elseif node.is=="number" then

			local left=parent:peek()
			if left and ( left.is=="value" or left.is=="number" or left.is=="list" ) then
				-- auto statement separator
				parent=parent:loose_list()
			end
			node:append(parent)

		elseif node.is=="symbol" then
			local greed=node:symbol_greed()
			if greed=="tight" and parent.greed~="tight" then

				local left=parent:pop()
				parent=trees.nodes.new_list(nil,parent) -- push new tight list
				parent.greed="tight"
				if left then -- might be an error but do not complain here
					left:append(parent)
				end
				node:append(parent)

			elseif greed=="tight" then -- continue in tight parent

				node:append(parent)

			else -- not tight so pop if parent is tight

				if parent.greed=="tight" then
					parent=parent.parent -- pop
				end
				
				if greed=="loose" then
					parent=parent:loose_list(node)
				else
					node:append(parent)
				end
			end

		end
	end

	return root
end
