sub module dependencies

Always be

	git submodule init
	git submodule update

lua is 5.2 which compiles to wasm and is mostly luajit compatible 
provided you don't use _ENV ( other minor issues but that is the main 
gotcha )

Generally I aim for lua code that works with either luajit or lua5.2 
and probably works with 5.3 or 5.4 but may need compat hacks.

This is the way.
