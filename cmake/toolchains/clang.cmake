set(CMAKE_C_COMPILER "/usr/bin/clang" CACHE FILEPATH "C compiler")
set(CMAKE_CXX_COMPILER "/usr/bin/clang++" CACHE FILEPATH "C++ compiler")

set(stdlib "-stdlib=libc++") # llvm
# set(stdlib "-stdlib=libstdc++") # gcc

set(CMAKE_CXX_FLAGS
	# "${stdlib} -fmodules -fimplicit-module-maps -fmodules-cache-path=${CMAKE_BINARY_DIR}/module-cache"
	# "${stdlib} -fmodules -fbuiltin-module-map -fmodules-cache-path=${CMAKE_BINARY_DIR}/module-cache"
	# "${stdlib} -fmodules"
	CACHE STRING "Initial C++ flags"
)
set(CMAKE_EXE_LINKER_FLAGS
	"${stdlib}"
	CACHE STRING "Initial exe linker flags"
)
set(CMAKE_SHARED_LINKER_FLAGS
	"${stdlib}"
	CACHE STRING "Initial shared linker flags"
)
unset(stdlib)
