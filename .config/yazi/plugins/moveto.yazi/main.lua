-- ~/.config/yazi/plugins/moveto.yazi/main.lua

local get_files = ya.sync(function(state)
  local selected = cx.active.selected
  local files = {}
  if #selected == 0 then
    local hovered = cx.active.current.hovered
    if hovered then
      table.insert(files, tostring(hovered.url))
    end
  else
    for _, url in pairs(selected) do
      table.insert(files, tostring(url))
    end
  end
  return files
end)

local function display_path(path)
  local home = os.getenv("HOME")
  if home and path == home then
    path = "~"
  elseif home and path:sub(1, #home + 1) == home .. "/" then
    path = "~/" .. path:sub(#home + 2)
  end
  return path:gsub("\r", "\\r"):gsub("\n", "\\n")
end

local function confirmation_body(files, dest)
  local lines = {
    string.format("%d item%s selected", #files, #files == 1 and "" or "s"),
    "",
    "From",
  }

  local shown = math.min(#files, 5)
  for i = 1, shown do
    lines[#lines + 1] = "  • " .. display_path(files[i])
  end
  if #files > shown then
    lines[#lines + 1] = string.format("  … and %d more", #files - shown)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Destination"
  lines[#lines + 1] = "  → " .. display_path(dest)
  return table.concat(lines, "\n")
end

local function choose_destination()
  if not os.getenv("HOME") then
    return nil, "HOME is not set"
  end

  local fzf_cmd = table.concat({
    -- Prune hidden directories instead of needlessly searching through them.
    -- NUL separators also preserve directory names containing newlines.
    "find \"$HOME\" -path '*/.*' -prune -o -type d -print0 | fzf",
    "--read0",
    "--print0",
    "--height=85%",
    "--layout=reverse",
    "--border=rounded",
    "--border-label=' Move destination '",
    "--info=inline",
    "--prompt='  Move to › '",
    "--header='  Select a directory · Esc cancels'",
    "--pointer='›'",
  }, " ")

  local permit = ui.hide()
  local ok, dest = pcall(function()
    local handle, open_err = io.popen(fzf_cmd)
    if not handle then
      error(open_err or "Could not start fzf")
    end
    local selected = handle:read("*a")
    local closed, _, exit_code = handle:close()

    if not selected or selected == "" then
      -- fzf uses 1 when there is no match and 130 when the user presses Esc.
      if closed or exit_code == 1 or exit_code == 130 then
        return nil
      end
      error("Destination picker exited with error " .. tostring(exit_code))
    elseif not closed then
      error("Destination picker exited with error " .. tostring(exit_code))
    end

    selected = selected:gsub("%z$", "")
    return selected
  end)
  permit:drop()

  if not ok then
    return nil, dest
  end
  return dest, nil
end

local function move_one(src, dest)
  local child, spawn_err = Command("mv")
    :arg({ "--interactive", "--verbose", "--", src, dest })
    :stdin(Command.INHERIT)
    :stdout(Command.INHERIT)
    :stderr(Command.INHERIT)
    :spawn()

  if not child then
    return false, "mv could not start: " .. tostring(spawn_err)
  end

  local status, wait_err = child:wait()
  if status and status.success then
    return true
  end

  if status and status.code then
    return false, "mv exited with code " .. tostring(status.code)
  end
  return false, "mv failed: " .. tostring(wait_err or "unknown error")
end

local function failure_summary(failures)
  local lines = { string.format("%d item%s could not be moved:", #failures, #failures == 1 and "" or "s") }
  local shown = math.min(#failures, 3)
  for i = 1, shown do
    lines[#lines + 1] = "• " .. display_path(failures[i].path) .. " — " .. failures[i].reason
  end
  if #failures > shown then
    lines[#lines + 1] = string.format("… and %d more", #failures - shown)
  end
  return table.concat(lines, "\n")
end

local function desktop_notify(title, body)
  local child = Command("notify-send")
    :arg({ title, body })
    :stdin(Command.NULL)
    :stdout(Command.NULL)
    :stderr(Command.NULL)
    :spawn()
  if child then
    child:wait()
  end
end

return {
  entry = function()
    local files = get_files()
    if #files == 0 then
      ya.notify({ title = "Moveto", content = "No files selected or hovered.", level = "warn", timeout = 3 })
      return
    end

    local dest, picker_err = choose_destination()
    if picker_err then
      ya.notify({ title = "Move picker error", content = tostring(picker_err), level = "error", timeout = 5 })
      return
    elseif not dest or dest == "" then
      return
    end

    local confirmed = ya.confirm {
      title = string.format(" 🚚 Move %d item%s? ", #files, #files == 1 and "" or "s"),
      body = confirmation_body(files, dest),
      pos = { "center", w = 78, h = math.min(20, 10 + math.min(#files, 5)) },
    }
    if not confirmed then
      return
    end

    local permit = ui.hide()
    local ok, failures = pcall(function()
      local result = {}
      for _, src in ipairs(files) do
        local moved, reason = move_one(src, dest)
        if not moved then
          result[#result + 1] = { path = src, reason = reason }
        end
      end
      return result
    end)
    permit:drop()
    ya.emit("refresh", {})

    if not ok then
      ya.notify({ title = "Move runtime error", content = tostring(failures), level = "error", timeout = 7 })
      return
    elseif #failures == 0 then
      ya.notify({
        title = "🚚 Move complete",
        content = string.format("%d item%s moved to %s", #files, #files == 1 and "" or "s", display_path(dest)),
        level = "info",
        timeout = 5,
      })
      desktop_notify("🚚 File(s) moved.", "File(s) moved to " .. display_path(dest) .. ".")
    else
      ya.notify({ title = "Move finished with errors", content = failure_summary(failures), level = "error", timeout = 8 })
    end
  end,
}
