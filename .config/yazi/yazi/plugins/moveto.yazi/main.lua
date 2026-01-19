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

local function log(msg)
  local logfile = io.open("/tmp/moveto.log", "a")
  if logfile then
    logfile:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. msg .. "\n")
    logfile:close()
  end
end

return {
  entry = function(self, job)
    local files = get_files()
    if #files == 0 then
      ya.notify({ title = "Moveto", content = "No files selected or hovered.", level = "warn", timeout = 3 })
      return
    end

    log("Started plugin")

    local permit = ui.hide()
    log("Hid UI")

    local ok, err = pcall(function()
      local fzf_cmd = "find ~ -type d -not -path '*/\\.*' | fzf --prompt 'Move to where? '"
      local handle = io.popen(fzf_cmd)
      local dest = handle:read("*l")
      handle:close()
      log("Ran fzf")

      os.execute("clear")

      if not dest or dest == "" then
        log("No dest selected")
        return
      end

      dest = dest:gsub("^~", os.getenv("HOME") or "")
      log("Dest: " .. dest)

      local tput_handle = io.popen("tput lines")
      local lines_str = tput_handle:read("*a"):gsub("\n", "")
      tput_handle:close()
      local lines = tonumber(lines_str) or 24
      local row = math.floor(lines / 3)
      print("\027[" .. row .. ";1H")
      print("\027[1m")

      log("Cleared and positioned screen")

      print("From:")
      for _, file in ipairs(files) do
        print(" " .. file)
      end

      print("To:")
      print(" " .. dest)
      print("")

      io.write("\tmove?[y/N] ")
      io.flush()

      local ans = io.read("*l") or ""
      print("\027[0m")

      log("Prompt answer: '" .. ans .. "'")

      if ans ~= "y" then
        os.execute("clear")
        log("Canceled move")
        return
      end

      -- Perform moves
      local success = true
      for _, src in ipairs(files) do
        local mv_cmd = string.format("mv -iv %q %q", src, dest)
        local status = os.execute(mv_cmd)
        if status ~= 0 and status ~= true then
          success = false
          log("Move failed for: " .. src)
        end
      end

      log("Moves done, success: " .. tostring(success))

      -- Removed refresh here—no more cx nil error
      -- Yazi usually auto-detects external fs changes on resume anyway

      os.execute("clear")
      log("Cleared terminal after move")

      if success then
        ya.notify({ title = "🚚 File(s) moved.", content = "File(s) moved to " .. dest .. ".", level = "info", timeout = 5 })
        local notify_cmd = string.format("notify-send '🚚 File(s) moved.' 'File(s) moved to %s.'", dest)
        os.execute(notify_cmd)
        log("Sent success notify")
      else
        ya.notify({ title = "Moveto Error", content = "Failed to move some files.", level = "error", timeout = 5 })
        log("Sent error notify")
      end
    end)

    permit:drop()
    log("Dropped permit")

    if not ok then
      ya.notify({ title = "Moveto Runtime Error", content = tostring(err), level = "error", timeout = 5 })
      log("Error: " .. tostring(err))
    end

    log("Ended plugin")
  end,
}
