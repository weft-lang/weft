# Weft for Neovim

This local plugin connects Neovim to Weft's generated Tree-sitter grammar and
the compiler's `lsp` handler configuration. It provides `.weft` filetype
detection, Tree-sitter highlighting, and LSP diagnostics, hover, formatting,
definition, and references.

With `lazy.nvim`, add the repository-local plugin to `init.lua`:

```lua
{
  dir = "~/Projects/weft/editors/nvim",
  name = "weft.nvim",
  lazy = false,
  opts = {},
}
```

Restart Neovim, then run this once:

```vim
:WeftInstallParser
```

Restart Neovim after installation: already-loaded parser libraries remain
cached for the session. Run the same command after pulling syntax or query
changes. The plugin checks query compatibility before highlighting; an older
parser produces a reinstall warning instead of a FileType traceback. The
installer validates both queries against the new parser before replacing the
installed library.

The command asks the checked-in Weft compiler to build the standalone typed
grammar generator, runs that generator and the pinned Tree-sitter CLI in
Neovim's cache, and installs the parser under Neovim's data directory. Keeping
the graph outside the ordinary compiler avoids linking editor data into every
compiler image. Generated grammar and C sources never modify the checkout. The
LSP launches the checked-in `./weft lsp` binary from the repository root; no
Mason package is required.

For grammar development, install the pinned CLI and run the complete generated
parser gate:

```sh
cd tree-sitter-weft
npm install
npm test
```

That checks deterministic generation, the Tree-sitter corpus, every production
module under `compiler/`, `stdlib/`, `runtime/`, and `tools/`, all positive
modules under `test/`, plus non-empty editor-query captures. `grammar.js`, C
parser sources, and parser libraries are generated under `build/` or temporary
cache directories and are intentionally excluded from git.

The plugin's parser-installation and query-compatibility lifecycle can also be
checked without loading your configuration or installing a parser:

```sh
nvim --headless -u NONE -i NONE -l editors/nvim/test/parser.lua
```

Useful checks after opening a `.weft` file:

```vim
:set filetype?
:checkhealth vim.treesitter
:LspInfo
```
