# neoranger.nvim

Open Ranger in a floating Neovim window. Requires Neovim 0.11+, Ranger 1.9+ with Python 3 on `PATH`, and macOS or Linux.

Install with lazy.nvim:

```lua
{
  "TheOddKn1ght/neoranger.nvim",
  lazy = false,
  opts = {},
}
```

Set `vim.g.mapleader` before loading plugins.

- `<leader>r`: open Ranger at the current file.
- Open a file or marked selection: open files in new Neovim tabs.
- `<C-g>` inside Ranger: set Neovim's global working directory to the displayed directory.
- `q`: quit the current Ranger tab; `Q`: quit all tabs.

Options go in `opts` (or `require("neoranger").setup`):

```lua
{ keymap = "<leader>r", cwd_keymap = "<C-g>", ranger_cmd = "ranger",
  window = { width = 0.8, height = 0.8, border = "rounded" } }
```

`:Neoranger [directory]` opens Ranger directly. Filenames containing newlines are unsupported.
