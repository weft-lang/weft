-- Run with: nvim --headless -u NONE -i NONE -l editors/nvim/test/parser.lua
-- Isolate the editor lifecycle from npm, filesystem mutation, and user config.
local host = vim
local root = host.fn.getcwd()

local function scenario(options)
  options = options or {}
  local seen = { queries = {}, overrides = {}, commands = {}, notices = {}, starts = 0, installs = 0, deletes = 0 }
  local fake = {
    fs = host.fs,
    deepcopy = host.deepcopy,
    list_extend = host.list_extend,
    tbl_extend = host.tbl_extend,
    log = host.log,
    cmd = function() end,
    schedule = function(callback) callback() end,
    notify = function(message) seen.notices[#seen.notices + 1] = message end,
    opt = { runtimepath = { append = function(_, path) seen.runtimepath = path end } },
    filetype = { add = function() end },
    lsp = { config = function() end, enable = function() end },
    api = {
      nvim_create_user_command = function(name, callback) seen.commands[name] = callback end,
      nvim_create_augroup = function() return 1 end,
      nvim_create_autocmd = function(_, spec) seen.attach = spec.callback end,
    },
    fn = {
      stdpath = function(kind) return "/test/" .. kind end,
      executable = function() return 1 end,
      mkdir = function() end,
      readfile = function(path) return { path } end,
    },
    uv = {
      fs_stat = function() return not options.missing and {} or nil end,
      os_getpid = function() return 123 end,
      hrtime = function() return 456 end,
      fs_open = function() return 1 end,
      fs_write = function(_, contents) return #contents end,
      fs_close = function() end,
      fs_chmod = function() return true end,
      fs_rename = function()
        assert(#seen.queries == 2, "both queries must validate before installation")
        seen.installs = seen.installs + 1
        return true
      end,
      fs_unlink = function() seen.deletes = seen.deletes + 1 end,
    },
    treesitter = {
      language_version = 15,
      language = { add = function()
        if options.unloadable then return nil, "parser cannot be loaded" end
        return true
      end },
      query = {
        parse = function(_, text)
          if options.stale and text:find("highlights", 1, true) then
            error('Invalid node type "implements"')
          end
        end,
        set = function(_, name, text) seen.overrides[name] = text end,
      },
      start = function() seen.starts = seen.starts + 1 end,
    },
    system = function(argv)
      local result = { code = 0, stdout = "generated data", stderr = "" }
      if argv[2] == "compile" then
        assert(argv[3] == "tools/tree_sitter_grammar.weft", "generator must compile in its owning checkout package")
      end
      if argv[4] == "query" then
        seen.queries[#seen.queries + 1] = argv
        if options.invalid_generated_query then
          result = { code = 1, stdout = "", stderr = "generated query is invalid" }
        end
      end
      return { wait = function() return result end }
    end,
  }
  setmetatable(fake, { __index = host })
  setmetatable(fake.fn, { __index = host.fn })
  vim = fake
  local plugin = dofile(root .. "/editors/nvim/lua/weft/init.lua")
  plugin.setup()
  plugin.setup()
  seen.attach({ buf = 7 })
  return seen
end

local valid = scenario()
assert(valid.runtimepath:match("tree%-sitter%-weft$"))
assert(valid.starts == 1 and #valid.notices == 0)
assert(next(valid.overrides) == nil)

local missing = scenario({ missing = true })
assert(not missing.runtimepath and missing.starts == 0)
assert(type(missing.commands.WeftInstallParser) == "function")

local stale = scenario({ stale = true })
assert(not stale.runtimepath and stale.starts == 0)
assert(stale.overrides.highlights == "" and stale.overrides.locals == "")
assert(#stale.notices == 1 and stale.notices[1]:find(":WeftInstallParser", 1, true))
stale.commands.WeftInstallParser()
assert(stale.installs == 1 and stale.starts == 0)
assert(stale.notices[2]:find("Restart Neovim", 1, true))
assert(stale.queries[1][6]:match("weft%-123%-456.so$"))

local unloadable = scenario({ unloadable = true })
assert(unloadable.starts == 0 and #unloadable.notices == 1)
assert(unloadable.notices[1]:find("parser cannot be loaded", 1, true))

local rejected = scenario({ stale = true, invalid_generated_query = true })
rejected.commands.WeftInstallParser()
assert(rejected.installs == 0 and rejected.deletes == 1)
assert(rejected.notices[2]:find("generated query is invalid", 1, true))

vim = host
print("Weft Neovim parser lifecycle: 5 scenarios passed")
