
local pplua=require("brutal.pplua")


-- perform very simple processing of command args
local parse=function(aa)
	local args={}
	local state=false
	for i,v in ipairs(aa or {}) do
		if state=="--" then
			args[#args+1]=v
		elseif v=="--" then state="--" -- we are done stop messing with the rest of the args
		elseif v:sub(1,2)=="--" then -- found an opt
			local s,e=v:find("=",1,true)
			if s then -- found a "=" so split and assign a string
				local a=v:sub(3,s-1):lower()
				local b=v:sub(e+1)
				args[a]=b
			else -- check for a no- prefix and assign a bool
				if v:sub(3,5)=="no-" then -- this is a false flag
					local a=v:sub(6):lower()
					args[a]=false
				else
					local a=v:sub(3):lower()
					args[a]=true
				end
			end
		else
			args[#args+1]=v
		end
	end

	return args
end


local args=parse({...})
args.cmd=args[1] or "help"

--for n,v in pairs(args) do print(n,v) end

if args.cmd=="help" then -- print help

print([[

brutal help
	Print this help.
	
brutal pp filein fileout
	Run the processor on filein and write it to fileout, If fileout is 
	missing then we will write to stdout and if filein is also missing 
	we will read from stdin.
	
	--search=".;.."
		Set search path for included files, we will look for them in 
		this order and only files below these given directories will be 
		included. EG we cant include /root/secret unless you add /root 
		as a search path.

]])

elseif args.cmd=="pp" then -- run pp

	args.filename=args[2]
	args.fileout=args[3]

	local pp={}
	if search then
		pp.search={}
		for s in args.search:gmatch("([^;]+)") do
			pp.search[#pp.search+1]=s
		end
	end
	
	pplua.create(pp)
	pp.root=pp:create_chunk()

	local data
	if args.filename then
		local fp=assert(io.open(args.filename,"rb"))
		data=fp:read("*all")
		fp:close()
	else
		data=io.read("*all")
	end
	pp:insert(pp.root,data)
	
	pp:run(pp.root)
	local text,map=pp:join(pp.root)
	
	if args.fileout then -- output file
		local fp=assert(io.open(args.fileout,"wb"))
		fp:write(text)
		fp:close()
	else -- output console
		print(text)
	end
	
else

	print("unknown command "..args.cmd)

end

