local M = {}

local configured = false
local tree_sitter_cli_version = "0.26.12"

local function normalize(path)
  return vim.fs.normalize(path)
end

local function plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return normalize(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source))))
end

local function repo_root()
  return normalize(plugin_root() .. "/../..")
end

local function grammar_root()
  return normalize(repo_root() .. "/tree-sitter-weft")
end

local function parser_path()
  return normalize(vim.fn.stdpath("data") .. "/site/parser/weft.so")
end

local function generated_grammar_root()
  return normalize(vim.fn.stdpath("cache") .. "/weft-tree-sitter")
end

local function command_environment()
  return {
    npm_config_cache = normalize(vim.fn.stdpath("cache") .. "/weft-npm"),
    XDG_CACHE_HOME = normalize(generated_grammar_root() .. "/cache"),
  }
end

local function tree_sitter_command()
  if vim.fn.executable("npx") == 1 then
    return { "npx", "--yes", "tree-sitter-cli@" .. tree_sitter_cli_version }
  end

  error("Weft parser installation requires npx")
end

local function run(command, args, options)
  options = options or {}
  local argv = vim.list_extend(vim.deepcopy(command), args)
  local result = vim.system(argv, {
    cwd = options.cwd or grammar_root(),
    env = command_environment(),
    text = options.text ~= false,
  }):wait()

  if result.code ~= 0 then
    local stderr = result.stderr or ""
    local detail = stderr ~= "" and stderr or (result.stdout or "")
    error(("%s failed:\n%s"):format(table.concat(argv, " "), detail))
  end

  return result
end

local function write_file(path, contents)
  if not contents then
    error("Weft grammar generator returned no output")
  end

  local fd, open_error = vim.uv.fs_open(path, "w", 420)
  if not fd then
    error(("could not create %s: %s"):format(path, open_error))
  end

  local written, write_error = vim.uv.fs_write(fd, contents, 0)
  vim.uv.fs_close(fd)
  if not written or written ~= #contents then
    error(("could not write %s: %s"):format(path, write_error or "short write"))
  end
end

local function load_parser(path)
  if vim.treesitter.language.add then
    vim.treesitter.language.add("weft", { path = path })
  else
    vim.treesitter.language.require_language("weft", path, true)
  end
end

local function install_parser()
  local target = parser_path()
  local generated_root = generated_grammar_root()
  local generated_source = normalize(generated_root .. "/grammar.js")
  local generator_source = normalize(repo_root() .. "/tools/tree_sitter_grammar.weft")
  local generator = normalize(generated_root .. "/weft-tree-sitter-grammar")
  local staged_parser = normalize(("%s/weft-%d-%s.so"):format(
    generated_root,
    vim.uv.os_getpid(),
    tostring(vim.uv.hrtime())
  ))
  vim.fn.mkdir(vim.fs.dirname(target), "p")
  vim.fn.mkdir(command_environment().npm_config_cache, "p")
  vim.fn.mkdir(normalize(generated_root .. "/src"), "p")

  local compiled_generator = run(
    { normalize(repo_root() .. "/weft") },
    { "compile", generator_source },
    { cwd = repo_root(), text = false }
  )
  write_file(generator, compiled_generator.stdout)
  local executable, chmod_error = vim.uv.fs_chmod(generator, 493)
  if not executable then
    error(("could not make %s executable: %s"):format(generator, chmod_error))
  end

  local generated = run({ generator }, {}, { cwd = repo_root() })
  write_file(generated_source, generated.stdout)

  local cli = tree_sitter_command()
  local abi = math.min(vim.treesitter.language_version or 14, 15)
  run(cli, {
    "generate",
    "--abi", tostring(abi),
    "--output", normalize(generated_root .. "/src"),
    generated_source,
  }, { cwd = generated_root })
  run(cli, { "build", "--output", staged_parser, generated_root }, { cwd = generated_root })

  local installed, install_error = vim.uv.fs_rename(staged_parser, target)
  if not installed then
    vim.uv.fs_unlink(staged_parser)
    error(("could not install %s: %s"):format(target, install_error))
  end
  load_parser(target)

  vim.notify(
    "Installed the Weft Tree-sitter parser with tree-sitter-cli " .. tree_sitter_cli_version,
    vim.log.levels.INFO
  )
  return target
end

local function start_treesitter(bufnr)
  local path = parser_path()
  if vim.uv.fs_stat(path) then
    local loaded = pcall(load_parser, path)
    if loaded then
      pcall(vim.treesitter.start, bufnr, "weft")
    end
  end
end

local function configure_treesitter()
  -- Neovim discovers queries under queries/{language} on runtimepath.
  vim.opt.runtimepath:append(grammar_root())

  vim.api.nvim_create_user_command("WeftInstallParser", function()
    local ok, result = pcall(install_parser)
    if not ok then
      vim.notify(result, vim.log.levels.ERROR)
      return
    end

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[bufnr].filetype == "weft" then
        pcall(vim.treesitter.start, bufnr, "weft")
      end
    end
  end, {
    desc = "Generate and install the Weft Tree-sitter parser",
    force = true,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("weft-treesitter", { clear = true }),
    pattern = "weft",
    callback = function(args)
      start_treesitter(args.buf)
    end,
  })
end

local function lsp_config()
  return {
    cmd = { normalize(repo_root() .. "/weft"), "lsp" },
    cmd_cwd = repo_root(),
    filetypes = { "weft" },
    root_markers = { "weft.toml", ".git" },
    workspace_required = false,
  }
end

local function configure_lsp()
  if vim.lsp.config and vim.lsp.enable then
    vim.lsp.config("weft", lsp_config())
    vim.lsp.enable("weft")
    return
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("weft-lsp", { clear = true }),
    pattern = "weft",
    callback = function()
      vim.lsp.start(vim.tbl_extend("force", lsp_config(), {
        name = "weft",
        root_dir = repo_root(),
      }))
    end,
  })
end

function M.setup()
  if configured then
    return
  end
  configured = true

  vim.cmd("filetype on")
  vim.filetype.add({ extension = { weft = "weft" } })
  configure_treesitter()
  configure_lsp()
end

return M
