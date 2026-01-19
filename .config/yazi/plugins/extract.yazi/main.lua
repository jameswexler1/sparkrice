-- ~/.config/yazi/plugins/extract.yazi/main.lua

local function log(msg)
  local logfile = io.open("/tmp/extract.log", "a")
  if logfile then
    logfile:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. msg .. "\n")
    logfile:close()
  end
end

log("PLUGIN LOADED: extract.yazi (version 2026-01-15)")

return {
  entry = function()
    log("ENTRY: Plugin triggered")

    local tab = cx.active
    local hovered = tab.current.hovered
    local hovered_url = hovered and hovered.url  -- This is already a Url object

    local selected = tab.selected or {}
    local selected_count = 0
    local selected_url = nil
    for u in pairs(selected) do
      selected_count = selected_count + 1
      if selected_count > 1 then
        ya.notify({ title = "Extract", content = "Please select or hover a single archive.", level = "warn", timeout = 5 })
        log("ABORT: Multiple files selected")
        return
      end
      selected_url = u  -- u is already a Url object
    end

    local url
    if selected_count == 1 then
      url = selected_url
    elseif hovered_url then
      url = hovered_url
    else
      ya.notify({ title = "Extract", content = "No file selected or hovered.", level = "warn", timeout = 5 })
      log("ABORT: No file")
      return
    end

    local file = tostring(url)  -- Convert Url to string path safely
    local basename = file:match("([^/]+)$") or file
    log("File: " .. file .. " | Basename: " .. basename)

    local ans, event = ya.input({ title = "Extract " .. basename .. "? [y/N]" })
    if event ~= 1 or (ans or ""):lower() ~= "y" then
      log("CANCELED by user")
      return
    end
    log("User confirmed")

    local lower = basename:lower()
    local cmd_prefix
    local patterns = {
      ["%.tar%.bz2$"] = "tar xjf",
      ["%.tbz2$"]     = "tar xjf",
      ["%.tar%.gz$"]  = "tar xzf",
      ["%.tgz$"]      = "tar xzf",
      ["%.tar%.xz$"]  = "tar xJf",  -- Correct for xz
      ["%.tar$"]      = "tar xf",
      ["%.bz2$"]      = "bunzip2",
      ["%.gz$"]       = "gunzip",
      ["%.rar$"]      = "unrar e",
      ["%.zip$"]      = "unzip",
      ["%.7z$"]       = "7z x",
      ["%.xz$"]       = "xz -d",
      ["%.z$"]        = "uncompress",
    }

    for pat, cmd in pairs(patterns) do
      if lower:match(pat) then
        cmd_prefix = cmd
        break
      end
    end

    if not cmd_prefix then
      ya.notify({ title = "Extract", content = "Unsupported archive: " .. basename, level = "warn", timeout = 5 })
      log("UNSUPPORTED format")
      return
    end

    local full_cmd = cmd_prefix .. " " .. ya.quote(file)
    log("EXEC: " .. full_cmd)

    local status = os.execute(full_cmd)
    ya.render()  -- Refresh view

    if status == 0 or status == true then
      ya.notify({ title = "📂 Extracted", content = basename .. " extracted successfully.", level = "info", timeout = 5 })
      log("SUCCESS")
    else
      ya.notify({ title = "Extract failed", content = "Command failed (missing tool?).", level = "error", timeout = 5 })
      log("FAIL: status " .. tostring(status))
    end

    log("END: Plugin finished")
  end,
}
