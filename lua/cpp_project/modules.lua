-- cpp_project.modules - go to definition on C++20 module imports, as a small
-- in-process LSP server that runs alongside clangd.
--
-- clangd answers nothing for the module name in `import :report;`, but
-- CMake's dependency scan already knows every module: each scanned TU gets a
-- p1689 `.ddi` file under <build>/CMakeFiles/<target>.dir/, whose `provides`
-- entries map a logical name ("sim:report") to its source file. The server
-- reads all of them once, when it initializes.
--
-- Being an LSP client (rather than a keymap-level fallback) is what makes gd
-- work with no extra logic: vim.lsp.buf.declaration/definition ask every
-- attached client and merge the answers. clangd returns nothing on an import
-- line and this server returns nothing anywhere else, so the existing
-- mappings get exactly one location and jump - tagstack, jumplist and all.
--
-- Its lifecycle follows clangd's: it attaches to a buffer when clangd does
-- (LspAttach), reads the .ddi files of clangd's own --compile-commands-dir,
-- and stops when that clangd stops. So the module map is re-read exactly when
-- clangd restarts, which is also what happens after a build - the thing that
-- rewrites the .ddi files.
--
-- Resolution is syntactic, via treesitter: the import_declaration under the
-- cursor names either a whole module (`import utils.math;`, used as is) or a
-- partition (`import :report;`), which is prefixed with the primary module
-- name from this file's own module_declaration - `sim` in both
-- `export module sim;` and `module sim:world;`.

local log = require("log").scope("cpp_modules")

local M = {}

M.NAME = "cpp_modules"

--- Every module the .ddi files under `build_dir` provide, as name -> source
--- paths. A name can collect several sources. Stale .ddi files outlive moved
--- or deleted sources (a build never cleans them up), so providers whose
--- source no longer exists are dropped. Whatever is left - the same module
--- name in two unrelated targets - is kept as is, and the LSP client shows
--- more than one location as a quickfix list.
---@param build_dir string
---@return table<string, string[]>
local function load(build_dir)
	local started = vim.uv.hrtime()
	local files = vim.fs.find(function(name)
		return name:match("%.ddi$") ~= nil
	end, { path = build_dir .. "/CMakeFiles", type = "file", limit = math.huge })

	local modules = {}
	local count = 0
	for _, file in ipairs(files) do
		local ok, ddi = pcall(function()
			return vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
		end)
		if not ok then
			log.warn("skipping unreadable %s: %s", file, ddi)
		else
			for _, rule in ipairs(ddi.rules or {}) do
				for _, provided in ipairs(rule.provides or {}) do
					local name, source = provided["logical-name"], provided["source-path"]
					if name and source and vim.uv.fs_stat(source) then
						local sources = modules[name]
						if not sources then
							sources = {}
							modules[name] = sources
							count = count + 1
						end
						if not vim.tbl_contains(sources, source) then
							sources[#sources + 1] = source
						end
					end
				end
			end
		end
	end

	log.info("loaded %d modules from %d .ddi files in %s (%.1fms)",
		count, #files, build_dir, (vim.uv.hrtime() - started) / 1e6)
	return modules
end

--- The file's top-level `module` declaration, if it has one.
---@param root TSNode
---@return TSNode?
local function module_declaration(root)
	for node in root:iter_children() do
		if node:type() == "module_declaration" then
			return node
		end
	end
end

--- The full name of the module imported at (`row`, `col`) in `bufnr`, or nil
--- when that position isn't on a named import. Header units
--- (`import <vector>;`) have no name to resolve and also give nil.
---@param bufnr integer
---@param row integer 0-based
---@param col integer 0-based, in bytes
---@return string?
local function import_at(bufnr, row, col)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "cpp")
	if not ok or not parser then
		return nil
	end
	local root = parser:parse()[1]:root()

	local node = root:named_descendant_for_range(row, col, row, col)
	while node and node:type() ~= "import_declaration" do
		-- `export import :x;` wraps the import, and the cursor on `export`
		-- lands on the wrapper rather than inside the import
		if node:type() == "export_declaration" then
			local child = node:named_child(0)
			node = child and child:type() == "import_declaration" and child or nil
			break
		end
		node = node:parent()
	end
	if not node then
		return nil
	end

	local name = node:field("name")[1]
	if name then
		return vim.treesitter.get_node_text(name, bufnr)
	end

	local partition = node:field("partition")[1]
	if not partition then
		return nil
	end
	local decl = module_declaration(root)
	local primary = decl and decl:field("name")[1]
	if not primary then
		log.warn("%s: partition import outside a module", vim.api.nvim_buf_get_name(bufnr))
		return nil
	end
	-- the partition node's text includes its leading ':'
	return vim.treesitter.get_node_text(primary, bufnr) .. vim.treesitter.get_node_text(partition, bufnr)
end

--- An LSP location at `source`'s module declaration, so the jump lands on
--- `export module sim:report;` rather than on line 1 (often a `module;` and
--- #include preamble). Read from disk, not from a loaded buffer, so unsaved
--- edits above the declaration can put it off by a few lines.
---@param source string
---@return lsp.Location
local function declaration_location(source)
	local row, col = 0, 0
	local ok, lines = pcall(vim.fn.readfile, source)
	if ok then
		local tree = vim.treesitter.get_string_parser(table.concat(lines, "\n"), "cpp"):parse()[1]
		local decl = module_declaration(tree:root())
		if decl then
			row, col = decl:start()
		end
	end
	local pos = { line = row, character = col }
	return { uri = vim.uri_from_fname(source), range = { start = pos, ["end"] = pos } }
end

--- The in-process server for `build_dir`, in the shape vim.lsp.start accepts
--- as `cmd`. Replies are scheduled rather than made inside request(): the
--- client only records a request as pending after request() returns, so a
--- synchronous reply would complete a request it doesn't know about yet.
---@param build_dir string
---@return fun(dispatchers: vim.lsp.rpc.Dispatchers): vim.lsp.rpc.PublicClient
local function server(build_dir)
	return function(dispatchers)
		local modules = {} ---@type table<string, string[]>
		local closing = false
		local last_id = 0

		local function locate(params)
			local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
			local name = import_at(bufnr, params.position.line, params.position.character)
			if not name then
				return {}
			end
			local sources = modules[name]
			if not sources then
				log.warn("no module %s in %s", name, build_dir)
				return {}
			end
			log.info("%s -> %s", name, table.concat(sources, ", "))
			return vim.tbl_map(declaration_location, sources)
		end

		local handlers = {
			initialize = function()
				modules = load(build_dir)
				return {
					capabilities = {
						positionEncoding = "utf-8",
						declarationProvider = true,
						definitionProvider = true,
					},
					serverInfo = { name = M.NAME },
				}
			end,
			shutdown = function()
				return vim.NIL
			end,
			["textDocument/declaration"] = locate,
			["textDocument/definition"] = locate,
		}

		local function terminate()
			if closing then
				return
			end
			closing = true
			dispatchers.on_exit(0, 0)
		end

		return {
			request = function(method, params, callback, notify_reply_callback)
				last_id = last_id + 1
				local id = last_id
				vim.schedule(function()
					if notify_reply_callback then
						notify_reply_callback(id)
					end
					local handler = handlers[method]
					if not handler then
						callback({ code = vim.lsp.protocol.ErrorCodes.MethodNotFound, message = method }, nil, id)
						return
					end
					local ok, result = pcall(handler, params)
					if ok then
						callback(nil, result, id)
					else
						log.error("%s failed: %s", method, result)
						callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = tostring(result) }, nil, id)
					end
				end)
				return true, id
			end,
			notify = function(method)
				if method == "exit" then
					terminate()
				end
				return true
			end,
			is_closing = function()
				return closing
			end,
			terminate = terminate,
		}
	end
end

--- The build dir a clangd client was started on - cpp_project.clangd always
--- passes it as --compile-commands-dir.
---@param client vim.lsp.Client
---@return string?
local function compile_commands_dir(client)
	for _, arg in ipairs(client.config.cmd or {}) do
		local dir = type(arg) == "string" and arg:match("^%-%-compile%-commands%-dir=(.+)$")
		if dir then
			return dir
		end
	end
end

-- our client id -> the clangd client id it follows. Keyed by clangd's id
-- rather than by root: a clangd restart can attach the new clangd before the
-- old one has finished exiting, and matching by root alone would then reuse
-- the old server, or stop the new one along with the old clangd.
local follows = {} ---@type table<integer, integer>

local registered = false
function M.setup()
	if registered then
		return
	end
	registered = true
	local group = vim.api.nvim_create_augroup("cpp_project.modules", { clear = true })

	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(args)
			local clangd = vim.lsp.get_client_by_id(args.data.client_id)
			if not clangd or clangd.name ~= "clangd" then
				return
			end
			local build_dir = compile_commands_dir(clangd)
			if not build_dir then
				return
			end
			local id = vim.lsp.start({
				name = M.NAME,
				cmd = server(build_dir),
				root_dir = clangd.config.root_dir,
			}, {
				bufnr = args.buf,
				reuse_client = function(client)
					return client.name == M.NAME and not client:is_stopped() and follows[client.id] == clangd.id
				end,
			})
			if id then
				follows[id] = clangd.id
			end
		end,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		group = group,
		callback = function(args)
			local clangd = vim.lsp.get_client_by_id(args.data.client_id)
			if not clangd or clangd.name ~= "clangd" then
				return
			end
			for id, clangd_id in pairs(follows) do
				local ours = clangd_id == clangd.id and vim.lsp.get_client_by_id(id)
				if ours then
					if clangd:is_stopped() then
						follows[id] = nil
						ours:stop()
					elseif ours.attached_buffers[args.buf] then
						vim.lsp.buf_detach_client(args.buf, id)
					end
				elseif clangd_id == clangd.id then
					follows[id] = nil
				end
			end
		end,
	})
end

return M
