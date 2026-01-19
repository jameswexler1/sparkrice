-- ~/.config/yazi/plugins/zip.yazi/main.lua

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

local function get_basenames(files)
  local basenames = {}
  for _, file in ipairs(files) do
    local url = Url(file)
    table.insert(basenames, url.name)  -- ← fixed: .name is a field, not a method()
  end
  return basenames
end

local function log(msg)
  local logfile = io.open("/tmp/zip.log", "a")
  if logfile then
    logfile:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. msg .. "\n")
    logfile:close()
  end
end

return {
  entry = function(self, job)
    local files = get_files()
    if #files == 0 then
      ya.notify({ title = "Zip", content = "No files selected or hovered.", level = "warn", timeout = 3 })
      return
    end

    local basenames = get_basenames(files)

    log("Started plugin")

    local permit = ui.hide()
    log("Hid UI")

    local ok, err = pcall(function()
      os.execute("clear")

      local tput_handle = io.popen("tput lines")
      local lines_str = tput_handle:read("*a"):gsub("\n", "")
      tput_handle:close()
      local lines = tonumber(lines_str) or 24
      local row = math.floor(lines / 3)
      print("\027[" .. row .. ";1H")
      print("\027[1m") -- Bold

      log("Cleared and positioned screen")

      -- List files (full paths, indented)
      for _, file in ipairs(files) do
        print("  " .. file)
      end
      print("")

      -- Name prompt
      io.write("Zip as (name.zip)? ")
      io.flush()
      local name = io.read("*l") or ""
      log("Entered name: '" .. name .. "'")

      os.execute("clear") -- Clean up after any fzf/cancel artifacts if needed

      if name == "" then
        log("No name entered")
        return
      end

      if not name:match("%.zip$") then
        name = name .. ".zip"
      end
      log("Final name: " .. name)

      -- Existence check + overwrite prompt
      local handle = io.open(name, "r")
      if handle then
        handle:close()
        io.write(string.format("File '%s' exists. Overwrite? [y/N] ", name))
        io.flush()
        local ow = (io.read("*l") or ""):lower()
        log("Overwrite answer: '" .. ow .. "'")
        if ow ~= "y" then
          os.execute("clear")
          log("Overwrite canceled")
          return
        end
        os.execute(string.format("rm -f %q", name))
        log("Deleted existing file")
      end

      -- Final confirmation
      io.write(string.format("Save as '%s'? [y/N] ", name))
      io.flush()
      local ans = (io.read("*l") or ""):lower()
      print("\027[0m") -- Reset bold
      log("Confirm answer: '" .. ans .. "'")

      if ans ~= "y" then
        os.execute("clear")
        log("Save canceled")
        return
      end

      -- Build and run zip command (flat archive using basenames)
      local quoted_basenames = {}
      for _, b in ipairs(basenames) do
        table.insert(quoted_basenames, string.format("%q", b))
      end
      local args = table.concat(quoted_basenames, " ")
      local zip_cmd = string.format("zip -r %q -- %s", name, args)
      log("Running: " .. zip_cmd)

      local status = os.execute(zip_cmd)

      os.execute("clear")
      log("Cleared terminal after zip")

      if status == 0 or status == true then
        ya.notify({ title = "📦 Archive created.", content = "Saved as " .. name .. ".", level = "info", timeout = 5 })
        local notify_cmd = string.format("notify-send '📦 Archive created.' 'Saved as %s'", name)
        os.execute(notify_cmd)
        log("Sent success notify")
      else
        log("Zip failed")
      end
    end)

    permit:drop()
    log("Dropped permit")

    if not ok then
      ya.notify({ title = "Zip Runtime Error", content = tostring(err), level = "error", timeout = 5 })
      log("Error: " .. tostring(err))
    end

    log("Ended plugin")
  end,
}
