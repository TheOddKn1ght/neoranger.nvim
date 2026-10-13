local M = {}
local uv = vim.uv

local defaults = {
  keymap = "<leader>r",
  cwd_keymap = "<C-g>",
  ranger_cmd = "ranger",
  window = { width = 0.8, height = 0.8, border = "rounded" },
}

local config = vim.deepcopy(defaults)
local active
local sessions = {}
local mapping
local serial = 0

local function notify(message, level)
  vim.notify("neoranger: " .. message, level or vim.log.levels.ERROR)
end

local function validate(opts)
  if type(opts) ~= "table" then
    error("neoranger: setup expects a table")
  end
  for key in pairs(opts) do
    if defaults[key] == nil then
      error("neoranger: unknown option " .. tostring(key))
    end
  end
  for _, key in ipairs({ "keymap", "cwd_keymap" }) do
    local value = opts[key]
    if value ~= nil and value ~= false and (type(value) ~= "string" or value == "") then
      error("neoranger: " .. key .. " must be a nonempty string or false")
    end
  end
  if type(opts.cwd_keymap) == "string" and opts.cwd_keymap:find("[%s%c]") then
    error("neoranger: cwd_keymap uses Ranger notation; use <Space> for a space")
  end
  if type(opts.cwd_keymap) == "string" and opts.cwd_keymap:lower():find("<leader>", 1, true) then
    error("neoranger: Ranger has no <leader>; use a literal key sequence")
  end
  if opts.ranger_cmd ~= nil and (type(opts.ranger_cmd) ~= "string" or opts.ranger_cmd == "") then
    error("neoranger: ranger_cmd must be an executable name or path")
  end
  if opts.window ~= nil then
    if type(opts.window) ~= "table" then
      error("neoranger: window must be a table")
    end
    for key, value in pairs(opts.window) do
      if key == "width" or key == "height" then
        if type(value) ~= "number" or not (value > 0 and value <= 1) then
          error("neoranger: window." .. key .. " must be greater than 0 and at most 1")
        end
      elseif key == "border" then
        local borders = { none = true, single = true, double = true, rounded = true, solid = true, shadow = true }
        if type(value) ~= "string" or not borders[value] then
          error("neoranger: invalid window.border")
        end
      else
        error("neoranger: unknown window option " .. tostring(key))
      end
    end
  end
end

local function geometry(options)
  local columns = vim.o.columns
  local lines = math.max(1, vim.o.lines - vim.o.cmdheight)
  local border = options.border
  if columns < 3 or lines < 3 then
    border = "none"
  end
  local padding = border == "none" and 0 or 2
  local width = math.max(1, math.min(math.floor(columns * options.width), columns - padding))
  local height = math.max(1, math.min(math.floor(lines * options.height), lines - padding))
  return {
    relative = "editor",
    style = "minimal",
    border = border,
    width = width,
    height = height,
    row = math.max(0, math.floor((lines - height - padding) / 2)),
    col = math.max(0, math.floor((columns - width - padding) / 2)),
  }
end

local function cleanup_files(session)
  uv.fs_unlink(session.files_path)
  uv.fs_unlink(session.cwd_path)
  uv.fs_rmdir(session.tempdir)
  sessions[session] = nil
end

local function close_display(session)
  if session.group then
    pcall(vim.api.nvim_del_augroup_by_id, session.group)
    session.group = nil
  end
  local was_current = session.win and vim.api.nvim_get_current_win() == session.win
  if was_current then
    vim.cmd.stopinsert()
  end
  if session.win and vim.api.nvim_win_is_valid(session.win) then
    pcall(vim.api.nvim_win_close, session.win, true)
  end
  if session.buf and vim.api.nvim_buf_is_valid(session.buf) then
    pcall(vim.api.nvim_buf_delete, session.buf, { force = true })
  end
  if was_current and vim.api.nvim_win_is_valid(session.origin) then
    vim.api.nvim_set_current_win(session.origin)
  end
  if active == session then
    active = nil
  end
end

local function read_result(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function open_files(content)
  local first_tab
  local seen = {}
  for path in content:gmatch("[^\n]+") do
    if not seen[path] then
      seen[path] = true
      local stat = uv.fs_stat(path)
      if not stat or stat.type ~= "file" then
        notify("Selected file is unavailable: " .. path)
      else
        local ok, err = pcall(function()
          local buf = vim.fn.bufadd(path)
          vim.fn.bufload(buf)
          vim.cmd.tabnew()
          vim.api.nvim_win_set_buf(0, buf)
          first_tab = first_tab or vim.api.nvim_get_current_tabpage()
        end)
        if not ok then
          notify("Cannot open " .. path .. ": " .. tostring(err))
        end
      end
    end
  end
  if first_tab and vim.api.nvim_tabpage_is_valid(first_tab) then
    vim.api.nvim_set_current_tabpage(first_tab)
  end
end

local function apply_results(session, directory, files)
  if directory and directory ~= "" then
    if not vim.api.nvim_win_is_valid(session.origin) then
      notify("The original window was closed; working directory was not changed")
      return
    end
    if vim.fn.isdirectory(directory) ~= 1 then
      notify("Selected directory is unavailable: " .. directory)
      return
    end
    vim.api.nvim_set_current_win(session.origin)
    -- Use :cd in the originating window, retaining Neovim's normal scope rules.
    vim.cmd("cd " .. vim.fn.fnameescape(directory))
    notify("Working directory: " .. vim.fn.getcwd(-1, -1), vim.log.levels.INFO)
  elseif files and files ~= "" then
    if vim.api.nvim_win_is_valid(session.origin) then
      vim.api.nvim_set_current_win(session.origin)
    end
    open_files(files)
  end
end

local function finish(session, code)
  if session.finished then
    return
  end
  session.finished = true
  local directory = read_result(session.cwd_path)
  local files = read_result(session.files_path)
  close_display(session)
  cleanup_files(session)
  if session.cancelled then
    return
  end
  if code ~= 0 then
    notify("Ranger exited with status " .. tostring(code))
    return
  end
  local ok, err = pcall(apply_results, session, directory, files)
  if not ok then
    notify(tostring(err))
  end
end

local function cancel(session)
  if not session or session.finished or session.cancelled then
    return
  end
  session.cancelled = true
  if session.job and session.job > 0 then
    pcall(vim.fn.jobstop, session.job)
  end
  close_display(session)
  if not session.job or session.job <= 0 then
    finish(session, 0)
  end
end

local function start_location(directory)
  if directory ~= nil then
    if type(directory) ~= "string" or directory == "" or directory:find("%z") then
      error("directory must be a nonempty path")
    end
    return vim.fn.fnamemodify(vim.fs.normalize(directory), ":p"), nil
  end
  local name = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype == "" and name ~= "" then
    local parent = vim.fs.dirname(name)
    if vim.fn.isdirectory(parent) == 1 then
      local stat = uv.fs_stat(name)
      return parent, stat and stat.type == "file" and name or nil
    end
  end
  return vim.fn.getcwd(), nil
end

local function ranger_argv(session, directory, selected)
  local args = { session.config.ranger_cmd, "--choosefiles=" .. session.files_path }
  if session.config.cwd_keymap then
    local action = table.concat({
      "if fm.loader.has_work():",
      "    fm.notify('neoranger: wait for file operations to finish before changing directory', bad=True)",
      "else:",
      "    import os",
      "    with open(os.environ['NEORANGER_CWD_FILE'], 'w', encoding='utf-8') as result:",
      "        result.write(fm.thisdir.path)",
      "    fm.exit()",
    }, "\n")
    -- The payload is a quoted Python string; paths travel through argv/env, never shell code.
    args[#args + 1] = "--cmd=map " .. session.config.cwd_keymap .. " eval exec(" .. vim.json.encode(action) .. ")"
  end
  if selected then
    args[#args + 1] = "--selectfile=" .. selected
  else
    args[#args + 1] = "--"
    args[#args + 1] = directory
  end
  return args
end

function M.open(directory)
  if vim.fn.has("nvim-0.11") ~= 1 then
    notify("Neovim 0.11 or later is required")
    return
  end
  if active then
    if active.win and vim.api.nvim_win_is_valid(active.win) then
      vim.api.nvim_set_current_win(active.win)
      vim.cmd.startinsert()
    end
    return
  end
  if vim.fn.executable(config.ranger_cmd) ~= 1 then
    notify("Ranger executable not found: " .. config.ranger_cmd)
    return
  end
  local ok, location, selected = pcall(start_location, directory)
  if not ok then
    notify(tostring(location))
    return
  end
  if vim.fn.isdirectory(location) ~= 1 then
    notify("Directory does not exist: " .. location)
    return
  end
  local tempdir = vim.fn.tempname()
  local created, err = uv.fs_mkdir(tempdir, 448)
  if not created then
    notify("Cannot create temporary directory: " .. tostring(err))
    return
  end
  local session = {
    config = vim.deepcopy(config),
    origin = vim.api.nvim_get_current_win(),
    tempdir = tempdir,
    files_path = tempdir .. "/files",
    cwd_path = tempdir .. "/cwd",
  }
  sessions[session] = true
  active = session
  ok, err = pcall(function()
    session.buf = vim.api.nvim_create_buf(false, true)
    session.win = vim.api.nvim_open_win(session.buf, true, geometry(session.config.window))
    vim.bo[session.buf].bufhidden = "wipe"
    vim.bo[session.buf].filetype = "neoranger"
    serial = serial + 1
    session.group = vim.api.nvim_create_augroup("neoranger_session_" .. serial, { clear = true })
    vim.api.nvim_create_autocmd("VimResized", {
      group = session.group,
      callback = function()
        if vim.api.nvim_win_is_valid(session.win) then
          vim.api.nvim_win_set_config(session.win, geometry(session.config.window))
        end
      end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
      group = session.group,
      pattern = tostring(session.win),
      callback = function()
        cancel(session)
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = session.group,
      buffer = session.buf,
      callback = function()
        cancel(session)
      end,
    })
    session.job = vim.fn.jobstart(ranger_argv(session, location, selected), {
      term = true,
      cwd = location,
      env = { NEORANGER_CWD_FILE = session.cwd_path },
      on_exit = function(_, code)
        vim.schedule(function()
          finish(session, code)
        end)
      end,
    })
    if session.job <= 0 then
      error("Cannot start Ranger (job result " .. tostring(session.job) .. ")")
    end
    vim.cmd.startinsert()
  end)
  if not ok then
    cancel(session)
    notify(tostring(err))
  end
end

function M.close()
  cancel(active)
end

function M.setup(opts)
  if opts == nil then
    opts = {}
  end
  validate(opts)
  if mapping then
    for _, current in ipairs(vim.api.nvim_get_keymap("n")) do
      if current.callback == mapping.callback then
        vim.keymap.del("n", mapping.lhs)
        break
      end
    end
    mapping = nil
  end
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  if config.keymap then
    local lhs = config.keymap:gsub("<[Ll][Ee][Aa][Dd][Ee][Rr]>", function()
      return vim.g.mapleader or "\\"
    end):gsub("<[Ll][Oo][Cc][Aa][Ll][Ll][Ee][Aa][Dd][Ee][Rr]>", function()
      return vim.g.maplocalleader or "\\"
    end)
    if next(vim.fn.maparg(lhs, "n", false, true)) then
      notify("Mapping " .. config.keymap .. " already exists; choose another keymap or use :Neoranger", vim.log.levels.WARN)
    else
      local callback = function()
        M.open()
      end
      vim.keymap.set("n", lhs, callback, { silent = true, desc = "Open Ranger" })
      mapping = { lhs = lhs, callback = callback }
    end
  end
  return M
end

vim.api.nvim_create_user_command("Neoranger", function(opts)
  M.open(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", complete = "dir", desc = "Open Ranger" })

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("neoranger", { clear = true }),
  callback = function()
    local pending = {}
    for session in pairs(sessions) do
      pending[#pending + 1] = session
    end
    for _, session in ipairs(pending) do
      cancel(session)
      if session.job and session.job > 0 then
        pcall(vim.fn.jobwait, { session.job }, 1000)
      end
      cleanup_files(session)
    end
  end,
})

return M
