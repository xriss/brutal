This is not the greatest language in the world, no, this is just a 
brutal hack.

![underconstruction](underconstruction.gif)

Obviously we will target WASM since it is the future, using binaryen to 
handle the lowlevel details

https://github.com/WebAssembly/binaryen

and probably using wasm-micro-runtime as a native runtime where needed

https://github.com/bytecodealliance/wasm-micro-runtime


My plan is to embed lua into it as a first class pre-processor, so 
includes and hacky macros.

What I need is something similar to glsl where you can hand off a text 
string to a library to compile, bind some input/output buffers and then 
have it run fast.

This is great for things like particles or cellular automation or image 
processing. The convenience overhead of languages like Lua or JS is too 
much in these use cases.

You can get a lot of utility from this sort of setup but that doesn't 
mean it could not also be a "normal" language eventually but the main 
focus is on snippets of dynamic code processing chunks of data. As such 
I don't think we really need strings or even memory allocations to 
start with.

The dynamic thing is a bit of a problem for web based wasm but I hope 
not having any state data will allow for simple replacement after each 
compile.
