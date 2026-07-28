local cmake = require("cpp_project.cmake")
local cmake_presets = require("cpp_project.cmake_presets")

---@type CMake.Config
local config = {
	cmake_preset_name = "gcc-debug",
	--build_dir = "build/Debug",
	--generator = "Ninja",
	--defines = {
	--	{ name = "CMAKE_EXPORT_COMPILE_COMMANDS", value = "ON" },
	--	{ name = "CMAKE_C_COMPILER",              value = "gcc" },
	--	{ name = "CMAKE_CXX_COMPILER",            value = "g++" },
	--},
}

local root = "~/t"

--local config_preset = {
--	build_dir = "~/t/build/gcc-debug",
--	cmake_preset_name = "gcc-debug",
--	defines = {
--		{ name = "CMAKE_BUILD_TYPE",              value = "Debug" },
--		{ name = "CMAKE_CXX_COMPILER",            value = "g++" },
--		{ name = "CMAKE_C_COMPILER",              value = "gcc" },
--		{ name = "CMAKE_EXPORT_COMPILE_COMMANDS", value = "ON" }
--	},
--	generator = "Ninja"
--}
local config_preset = cmake_presets.resolve(root, "gcc-debug")

--vim.print(cmake_presets.available(root))
--vim.print(cmake_presets.list(root))
--vim.print(cmake_presets.resolve(root, "gcc-debug"))

--vim.print(config)
--vim.print(config_preset)
--vim.print(cmake.command_parts(config, config_preset))

--require("cmake_menu.tab_project").open()
--require("cmake_menu.tab_configure").open()
require("cmake_menu.tabs").open("Test")
