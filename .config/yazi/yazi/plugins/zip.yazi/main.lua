-- ~/.config/yazi/plugins/zip.yazi/main.lua

local get_urls = ya.sync(function()
  local selected = cx.active.selected or {}
  local urls = {}
  if #selected == 0 then
    local hovered = cx.active.current.hovered
    if hovered then
      table.insert(urls, hovered.url)
    end
  else
    for _, url in pairs(selected) do
      table.insert(urls, url)
    end
  end
  return urls
end)

local function get_basenames(urls)
  local basenames = {}
  for _, url in ipairs(urls) do
    table.insert(basenames, url.name)  -- field
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
  entry = function()
    local urls = get_urls()
    if #urls == 0 then
      ya.notify({ title = "Zip", content = "No files selected or hovered.", level = "warn", timeout = 3 })
      return
    end

    local basenames = get_basenames(urls)
    log("Started plugin")

    local ok, err = pcall(function()
      -- Name prompt (popup instead of terminal)
      local name, status = ya.input({
        title = "Zip as (name.zip)?",
        value = "",  -- no default, like original
        pos = { "center", w = 70 },
      })
      log("Entered name: '" .. (name or "") .. "'")
      if status ~= 1 or not name or name == "" then
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
        local ow, ow_status = ya.input({
          title = string.format("File '%s' exists. Overwrite? [y/N]", name),
          value = "",
          pos = { "center", w = 50 },
        })
        log("Overwrite answer: '" .. (ow or "") .. "'")
        if ow_status ~= 1 or (ow or ""):lower() ~= "y" then
          log("Overwrite canceled")
          return
        end
        os.execute(string.format("rm -f %q", name))
        log("Deleted existing file")
      end

      -- Final confirmation
      local ans, ans_status = ya.input({
        title = string.format("Save as '%s'? [y/N]", name),
        value = "",
        pos = { "center", w = 60 },
      })
      log("Confirm answer: '" .. (ans or "") .. "'")
      if ans_status ~= 1 or (ans or ""):lower() ~= "y" then
        log("Save canceled")
        return
      end

      -- Build and run zip command (flat archive using basenames)
      local quoted_basenames = {}
      for _, b in ipairs(basenames) do
        table.insert(quoted_basenames, string.format("%q", b))
      end
      local args = table.concat(quoted_basenames, " ")
      local zip_cmd = string.format("zip -q -r %q -- %s", name, args)  -- Added -q for quiet mode
      log("Running: " .. zip_cmd)
      local status = os.execute(zip_cmd)
      if status == 0 or status == true then
        ya.notify({ title = "📦 Archive created.", content = "Saved as " .. name .. ".", level = "info", timeout = 5 })
        local notify_cmd = string.format("notify-send '📦 Archive created.' 'Saved as %s' 2>/dev/null || true", name)
        os.execute(notify_cmd)
        log("Sent success notify")
        ya.manager_emit("refresh", {})  -- Refresh the manager to update the file list and clear any potential artifacts
      else
        log("Zip failed")
      end
    end)

    log("Ended plugin")
    if not ok then
      ya.notify({ title = "Zip Runtime Error", content = tostring(err), level = "error", timeout = 5 })
      log("Error: " .. tostring(err))
    end
  end,
}
