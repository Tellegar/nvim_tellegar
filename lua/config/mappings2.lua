local tasks = require("tasks")
local cmake_utils = require("tasks.cmake_utils.cmake_utils")
local cmake_presets = require("tasks.cmake_utils.cmake_presets")
local ProjectConfig = require("tasks.project_config")

vim.keymap.set("n", "<leader>cC", [[:Task start cmake configure<cr>]], { silent = true })
vim.keymap.set("n", "<leader>cD", [[:Task start cmake configureDebug<cr>]], { silent = true })
vim.keymap.set("n", "<leader>cP", [[:Task start cmake reconfigure<cr>]], { silent = true })
vim.keymap.set("n", "<leader>cT", [[:Task start cmake ctest<cr>]], { silent = true })
vim.keymap.set("n", "<leader>cK", [[:Task start cmake clean<cr>]], { silent = true })
vim.keymap.set("n", "<leader>ct", [[:Task set_module_param cmake target<cr>]], { silent = true })
vim.keymap.set("n", "<C-c>", [[:Task cancel<cr>]], { silent = true })
vim.keymap.set("n", "<leader>cr", [[:Task start cmake run<cr>]], { silent = true })
vim.keymap.set("n", "<F7>", [[:Task start cmake debug<cr>]], { silent = true })
vim.keymap.set("n", "<leader>cb", [[:Task start cmake build<cr>]], { silent = true })
vim.keymap.set("n", "<leader>cB", [[:Task start cmake build_all<cr>]], { silent = true })

-- C++20 modules: the dyndep-scanned ".modmap" response files (which give clangd
-- -x c++-module/-fmodule-output/-fmodule-file flags) only get (re)written by an
-- actual ninja build. clangd doesn't notice when their contents change, so after
-- building a module for the first time, or after changing a module's
-- import/export graph, restart clangd to pick the new flags back up.
--
-- Note: this intentionally does NOT reuse cmake_utils.reconfigureClangd(). That
-- helper stops every client named "clangd" (including the throwaway rootless
-- client clangd spins up when you `gd` into a std/system header with no
-- compile_commands.json entry) but only reloads the single current buffer
-- afterwards - so if your own file isn't the current buffer when the 500ms
-- timer fires, its client gets killed and never comes back. Here we only touch
-- clients that share the current buffer's root_dir, and reload every buffer
-- that was actually attached, not just the current one.
local function restartClangd()
	local cur = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
	if not cur then
		vim.notify("No clangd client attached to current buffer", vim.log.levels.WARN)
		return
	end

	local root = cur.root_dir
	local bufs_to_reload = {}
	for _, client in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
		if client.root_dir == root then
			for bufnr in pairs(client.attached_buffers or {}) do
				bufs_to_reload[bufnr] = true
			end
			if not client:is_stopped() then
				client:stop()
			end
		end
	end

	vim.lsp.config("clangd", {
		cmd = cmake_utils.currentClangdArgs(),
		capabilities = { offsetEncoding = { "utf-8" } },
	})

	vim.defer_fn(function()
		for bufnr in pairs(bufs_to_reload) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_call(bufnr, function() vim.cmd("edit") end)
			end
		end
	end, 500)
end

vim.keymap.set("n", "<leader>cx", restartClangd, { silent = true, desc = "restart clangd (pick up new module BMI flags)" })

-- open ccmake in embedded terminal
local function openCCMake()
	local build_dir = tostring(require("tasks.cmake_utils.cmake_utils").getBuildDir())
	vim.cmd([[bo sp term://ccmake ]] .. build_dir)
end
vim.keymap.set("n", "<leader>cc", openCCMake, { silent = true })

-- if project is using presets, provide preset selection for both <leader>cv and <leader>ck
-- if not, provide build type (<leader>cv) and kit (<leader>ck) selection

local function selectPreset()
	local availablePresets = cmake_presets.parse("buildPresets")

	vim.ui.select(availablePresets, { prompt = "Select build preset" }, function(choice, idx)
		if not idx then
			return
		end
		local projectConfig = ProjectConfig:new()
		if not projectConfig["cmake"] then
			projectConfig["cmake"] = {}
		end

		projectConfig["cmake"]["build_preset"] = choice

		-- autoselect will invoke projectConfig:write()
		cmake_utils.autoselectConfigurePresetFromCurrentBuildPreset(projectConfig)

	end)
end

local function selectBuildKitOrPreset()
	if cmake_utils.shouldUsePresets() then
		selectPreset()
	else
		tasks.set_module_param("cmake", "build_kit")
	end
end

vim.keymap.set("n", "<leader>ck", selectBuildKitOrPreset, { silent = true })

local function selectBuildTypeOrPreset()
	if cmake_utils.shouldUsePresets() then
		selectPreset()
	else
		tasks.set_module_param("cmake", "build_type")
	end
end

vim.keymap.set("n", "<leader>cv", selectBuildTypeOrPreset, { silent = true })
