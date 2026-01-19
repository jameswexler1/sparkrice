-- ~/.config/yazi/plugins/copyto.yazi/main.lua

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
  local logfile = io.open("/tmp/copyto.log", "a")
  if logfile then
    logfile:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. msg .. "\n")
    logfile:close()
  end
end

return {
  entry = function(self, job)
    local files = get_files()
    if #files == 0 then
      ya.notify({ title = "Copyto", content = "No files selected or hovered.", level = "warn", timeout = 3 })
      return
    end

    log("Started plugin")

    local permit = ui.hide()
    log("Hid UI")

    local ok, err = pcall(function()
      local fzf_cmd = "find ~ -type d -not -path '*/\\.*' | fzf --prompt 'Copy to where? '"
      local handle = io.popen(fzf_cmd)
      local dest = handle:read("*l")
      handle:close()
      log("Ran fzf")

      -- Always clear after fzf (cleanup on select or cancel)
      os.execute("clear")

      if not dest or dest == "" then
        log("No dest selected")
        return
      end

      dest = dest:gsub("^~", os.getenv("HOME") or "")
      log("Dest: " .. dest)

      -- Position cursor ~1/3 down
      local tput_handle = io.popen("tput lines")
      local lines_str = tput_handle:read("*a"):gsub("\n", "")
      tput_handle:close()
      local lines = tonumber(lines_str) or 24  -- fallback
      local row = math.floor(lines / 3)
      print("\027[" .. row .. ";1H")
      print("\027[1m") -- Bold

      log("Cleared and positioned screen")

      print("From:")
      for _, file in ipairs(files) do
        print(" " .. file)
      end

      print("To:")
      print(" " .. dest)
      print("")

      -- Prompt without trailing newline, cursor stays after
      io.write("\tcopy?[y/N] ")
      io.flush()

      local ans = io.read("*l") or ""
      print("\027[0m") -- Reset bold

      log("Prompt answer: '" .. ans .. "'")

      if ans ~= "y" then
        os.execute("clear")
        log("Canceled copy")
        return
      end

      -- Perform copies
-- Perform copies
local success = true
for _, src in ipairs(files) do
  local cp_cmd = string.format("cp -ivr %q %q", src, dest)
  local status = os.execute(cp_cmd)
  log("os.execute status for " .. src .. ": " .. tostring(status))
  if status ~= 0 and status ~= true then
    success = false
    log("Copy failed for: " .. src)
    -- Optional: break here if you want to stop on first error
    -- break
  end
end

      log("Copies done, success: " .. tostring(success))

      os.execute("clear")
      log("Cleared terminal after copy")

      if success then
        ya.notify({ title = "📋 File(s) copied.", content = "File(s) copied to " .. dest .. ".", level = "info", timeout = 5 })
        local notify_cmd = string.format("notify-send '📋 File(s) copied.' 'File(s) copied to %s.'", dest)
        os.execute(notify_cmd)
        log("Sent success notify")
      else
        ya.notify({ title = "Copyto Error", content = "Failed to copy some files.", level = "error", timeout = 5 })
        log("Sent error notify")
      end
    end)

    permit:drop()
    log("Dropped permit")

    if not ok then
      ya.notify({ title = "Copyto Runtime Error", content = tostring(err), level = "error", timeout = 5 })
      log("Error: " .. tostring(err))
    end

    log("Ended plugin")
  end,
}
