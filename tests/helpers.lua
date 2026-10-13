local H = {}
H.root = vim.fn.getcwd()
H.temp = vim.fn.tempname()
vim.fn.mkdir(H.temp, "p")
H.temp = vim.uv.fs_realpath(H.temp)
vim.opt.runtimepath:prepend(H.root)
vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.o.columns = 100
vim.o.lines = 32
vim.g.mapleader = " "

H.plugin = require("neoranger")
H.messages = {}
vim.notify = function(message, level)
  H.messages[#H.messages + 1] = { message = message, level = level }
end

function H.eq(actual, expected, label)
  assert(vim.deep_equal(actual, expected), (label or "mismatch") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual))
end

function H.wait(condition, label, timeout)
  assert(vim.wait(timeout or 5000, condition, 10), "timed out: " .. label)
end

function H.write(path, lines)
  vim.fn.writefile(lines or { "fixture" }, path)
  return path
end

function H.text(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return ""
  end
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

function H.contains(buf, text)
  return H.text(buf):find(text, 1, true) ~= nil
end

function H.message(text)
  for _, item in ipairs(H.messages) do
    if item.message:find(text, 1, true) then
      return true
    end
  end
  return false
end

function H.handle()
  local buf = vim.api.nvim_get_current_buf()
  H.eq(vim.bo[buf].filetype, "neoranger", "plugin buffer")
  return { buf = buf, win = vim.api.nvim_get_current_win(), job = vim.b[buf].terminal_job_id }
end

function H.send(handle, text)
  vim.fn.chansend(handle.job, text)
end

function H.closed(handle)
  H.wait(function()
    return not vim.api.nvim_buf_is_valid(handle.buf)
      and not vim.api.nvim_win_is_valid(handle.win)
      and vim.fn.jobwait({ handle.job }, 0)[1] ~= -1
  end, "session closes")
  vim.wait(30, function() return false end, 10)
end

function H.reset()
  H.plugin.close()
  vim.wait(50, function() return false end, 10)
  vim.cmd.stopinsert()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.cmd.enew({ bang = true })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= vim.api.nvim_get_current_buf() then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  vim.cmd("cd " .. vim.fn.fnameescape(H.temp))
  vim.o.autochdir = false
  H.messages = {}
  vim.o.columns = 100
  vim.o.lines = 32
end

function H.run(tests)
  local passed = 0
  local failed = 0
  for _, test in ipairs(tests) do
    H.reset()
    local ok, err = xpcall(test[2], debug.traceback)
    if ok then
      passed = passed + 1
      print("PASS " .. test[1])
    else
      failed = failed + 1
      print("FAIL " .. test[1] .. "\n" .. tostring(err))
      for _, msg in ipairs(H.messages) do
        print(msg.message)
      end
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].filetype == "neoranger" then
          print("Ranger screen:\n" .. H.text(buf))
        end
      end
    end
  end
  H.reset()
  vim.cmd("cd " .. vim.fn.fnameescape(H.root))
  vim.fn.delete(H.temp, "rf")
  print(string.format("%d passed, %d failed", passed, failed))
  vim.cmd(failed == 0 and "qa!" or "cquit 1")
end

return H
