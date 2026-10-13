# neoranger.nvim

Use [Ranger](https://github.com/ranger/ranger) inside a floating Neovim window to open files or choose your working directory.

- `<leader>r` opens Ranger at the current file, or in Neovim's working directory for an unnamed or special buffer.
- Open a file in Ranger to open it in a new Neovim tab. Mark several files with Space, then open the selection to create a tab for each file; the first tab receives focus.
- `<C-g>` in Ranger's browser sets Neovim's global working directory to the **displayed directory**, closes Ranger, and returns to the original window. Navigate into the desired directory before confirming.
- `q` quits Ranger (or closes its current tab). `Q` quits all Ranger tabs. Quitting and selecting files do not change Neovim's working directory.

## Requirements

- Neovim 0.11 or later on macOS or Linux.
- Ranger 1.9 or later, running with Python 3, available on `PATH` or configured with `ranger_cmd`.

There are no additional Neovim plugin dependencies.

## Installation

Add this spec to your [lazy.nvim](https://github.com/folke/lazy.nvim) plugin list:

```lua
{
  "TheOddKn1ght/neoranger.nvim",
  lazy = false,
  opts = {},
}
```

Set `vim.g.mapleader` before loading plugins. With Space as the leader, the default shortcut is Space followed by lowercase `r`.

## Configuration

```lua
require("neoranger").setup({
  keymap = "<leader>r",
  cwd_keymap = "<C-g>",
  ranger_cmd = "ranger",
  window = {
    width = 0.8,
    height = 0.8,
    border = "rounded",
  },
})
```

With lazy.nvim, place these options in the plugin spec's `opts` table instead.

| Option | Meaning |
| --- | --- |
| `keymap` | Normal-mode Neovim shortcut. `false` disables it. An existing mapping is preserved and a warning is shown. |
| `cwd_keymap` | Ranger browser shortcut for directory confirmation. `false` disables it. Uses Ranger key notation, such as `<C-g>`, `<F6>`, or `gc`; Neovim's `<leader>` is not supported here. |
| `ranger_cmd` | Executable name or path, without shell arguments. |
| `window.width`, `window.height` | Fractions of the editor size, greater than 0 and at most 1. |
| `window.border` | `none`, `single`, `double`, `rounded`, `solid`, or `shadow`. |

For example, use `<leader>e` to open Ranger and `gc` inside Ranger to choose a directory:

```lua
require("neoranger").setup({ keymap = "<leader>e", cwd_keymap = "gc" })
```

The directory mapping overrides that key only inside Ranger sessions launched by this plugin. Your Ranger configuration files are not edited. Existing Ranger settings and mappings otherwise apply. Active file operations block directory confirmation; confirm again after they finish.

## Commands and Lua API

```vim
:Neoranger
:Neoranger /path/to/directory
```

```lua
require("neoranger").open()                       -- Current file's directory
require("neoranger").open("/path/to/directory")   -- Explicit start directory
require("neoranger").close()                      -- Cancel and stop this session
```

Repeated opening focuses the existing Ranger session. The floating window follows editor resizing. Unsaved buffers are retained, and no files are written automatically.

Directory confirmation executes `:cd` in the originating window. Other windows or tabs with their own `:lcd` or `:tcd` retain Neovim's normal local-directory behavior. The plugin does not change `'autochdir'`; if enabled, Neovim may subsequently change directory when you switch buffers. If the original window or selected directory disappears, the directory change is skipped with a message.

Ranger's file-selection protocol separates paths with newlines, so filenames containing newlines are unsupported. Spaces, Unicode, and shell punctuation are supported. Selected directories are skipped when opening files; use directory confirmation to change the working directory.

