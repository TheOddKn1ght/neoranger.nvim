local H = dofile("tests/helpers.lua")
local executable = vim.fn.exepath("ranger")
assert(executable ~= "", "Ranger must be installed for the smoke tests")
local wrapper = H.temp .. "/clean-ranger"
H.write(wrapper, {
  "#!/bin/sh",
  "exec " .. vim.fn.shellescape(executable) .. " --clean --cmd='set preview_files false' --cmd='set flushinput false' \"$@\"",
})
assert(vim.uv.fs_chmod(wrapper, 448))

local files = H.temp .. "/files % # ' | $() ü"
vim.fn.mkdir(files, "p")
local alpha = H.write(files .. "/alpha.txt")
local beta = H.write(files .. "/beta % # ' | $() ü.txt")
local directories = H.temp .. "/directories"
local target = directories .. "/target % # ' | $() ü"
vim.fn.mkdir(target, "p")
H.write(target .. "/inside.txt")
H.write(directories .. "/outside.txt")

local function setup(opts)
  H.plugin.setup(vim.tbl_deep_extend("force", { ranger_cmd = wrapper }, opts or {}))
end

local function open(directory, ready_text)
  H.plugin.open(directory)
  local h = H.handle()
  H.wait(function() return H.contains(h.buf, ready_text) end, "Ranger shows " .. ready_text, 10000)
  return h
end

local tests = {
  { "real Ranger Enter opens the highlighted file", function()
    setup()
    vim.cmd("edit " .. vim.fn.fnameescape(beta))
    local cwd = vim.fn.getcwd(-1, -1)
    local h = open(nil, "alpha.txt")
    H.send(h, "\r")
    H.closed(h)
    H.eq(#vim.api.nvim_list_tabpages(), 2)
    H.eq(vim.api.nvim_buf_get_name(0), beta)
    H.eq(vim.fn.getcwd(-1, -1), cwd)
  end },
  { "real Ranger marks multiple files and opens separate tabs", function()
    setup()
    vim.cmd("edit " .. vim.fn.fnameescape(alpha))
    local h = open(nil, "alpha.txt")
    H.send(h, "  \r")
    H.closed(h)
    local tabs = vim.api.nvim_list_tabpages()
    H.eq(#tabs, 3)
    H.eq(vim.api.nvim_get_current_tabpage(), tabs[2])
    H.eq(vim.api.nvim_buf_get_name(0), alpha)
    H.eq(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_get_win(tabs[3]))), beta)
  end },
  { "real Ranger starts with one tab when highlighting a file", function()
    setup()
    vim.cmd("edit " .. vim.fn.fnameescape(alpha))
    local cwd = vim.fn.getcwd(-1, -1)
    local h = open(nil, "alpha.txt")
    H.send(h, "q")
    H.closed(h)
    H.eq(#vim.api.nvim_list_tabpages(), 1)
    H.eq(vim.fn.getcwd(-1, -1), cwd)
  end },
  { "real Ranger navigation and Ctrl-g change the global cwd", function()
    setup()
    local origin = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
    local h = open(directories, "outside.txt")
    H.send(h, "ggl")
    H.wait(function() return H.contains(h.buf, "inside.txt") end, "Ranger enters target directory")
    H.send(h, "\7")
    H.closed(h)
    H.eq(vim.fn.getcwd(-1, -1), target)
    H.eq(vim.api.nvim_get_current_win(), origin)
    H.eq(#vim.api.nvim_list_tabpages(), 1)
    H.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "unsaved" })
    assert(vim.bo.modified)
  end },
  { "real Ranger quitting after navigation leaves cwd unchanged", function()
    setup()
    local cwd = vim.fn.getcwd(-1, -1)
    local h = open(directories, "outside.txt")
    H.send(h, "ggl")
    H.wait(function() return H.contains(h.buf, "inside.txt") end, "Ranger enters target directory")
    H.send(h, "q")
    H.closed(h)
    H.eq(vim.fn.getcwd(-1, -1), cwd)
    H.eq(#vim.api.nvim_list_tabpages(), 1)
  end },
  { "real Ranger custom directory key and disabled key", function()
    setup({ cwd_keymap = "gc" })
    local h = open(files, "alpha.txt")
    H.send(h, "gc")
    H.closed(h)
    H.eq(vim.fn.getcwd(-1, -1), files)
    setup({ cwd_keymap = false })
    h = open(directories, "outside.txt")
    H.send(h, "\7")
    vim.wait(100, function() return false end, 10)
    assert(vim.api.nvim_buf_is_valid(h.buf))
    H.send(h, "q")
    H.closed(h)
    H.eq(vim.fn.getcwd(-1, -1), files)
  end },
  { "real Ranger refuses directory confirmation during active file operations", function()
    setup()
    local cwd = vim.fn.getcwd(-1, -1)
    local h = open(files, "alpha.txt")
    H.send(h, ":eval fm.loader.has_work = lambda: True\r")
    vim.wait(100, function() return false end, 10)
    H.send(h, "\7")
    H.wait(function() return H.contains(h.buf, "wait for file operations") end, "active file-operation warning")
    H.eq(vim.fn.getcwd(-1, -1), cwd)
    H.send(h, ":eval fm.loader.has_work = lambda: False\r")
    vim.wait(100, function() return false end, 10)
    H.send(h, "\7")
    H.closed(h)
    H.eq(vim.fn.getcwd(-1, -1), files)
  end },
}

H.run(tests)
