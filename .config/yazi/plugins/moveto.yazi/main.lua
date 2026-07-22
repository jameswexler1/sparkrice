-- ~/.config/yazi/plugins/moveto.yazi/main.lua

local MAX_MATCHES = 250
local POPUP_WIDTH = 76
local POPUP_HEIGHT = 13
local CACHE_SECONDS = 300

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

local function popup_area(available)
  if available.w < 18 or available.h < 10 then
    return nil
  end

  local width = math.min(POPUP_WIDTH, available.w - 4)
  local center_y = available.y + math.floor(available.h / 2)
  local y = math.max(available.y + 4, center_y - 4)
  local height = math.min(POPUP_HEIGHT, available.y + available.h - y - 1)
  if height < 5 then
    return nil
  end

  return ui.Rect {
    x = available.x + math.floor((available.w - width) / 2),
    y = y,
    w = width,
    h = height,
  }
end

local function setup(state)
  if state.modal_id then
    return
  end

  state.visible = false
  state.matches = {}
  state.cursor = 0
  state.match_count = 0
  state.message = nil

  local Popup = { _id = "moveto-popup" }

  function Popup:new(area)
    return setmetatable({ _area = area }, { __index = self })
  end

  function Popup:reflow()
    return state.visible and { self } or {}
  end

  function Popup:redraw()
    if not state.visible then
      return {}
    end

    local area = popup_area(self._area)
    if not area then
      return {}
    end

    local list_area = ui.Rect {
      x = area.x + 2,
      y = area.y + 1,
      w = math.max(0, area.w - 4),
      h = math.max(0, area.h - 3),
    }
    local footer_area = ui.Rect {
      x = area.x + 2,
      y = area.y + area.h - 2,
      w = math.max(0, area.w - 4),
      h = 1,
    }
    local title_area = ui.Rect {
      x = area.x + 2,
      y = area.y,
      w = math.min(11, math.max(0, area.w - 4)),
      h = 1,
    }

    local lines = {}
    local footer
    if state.message then
      lines[1] = ui.Line(state.message):align(ui.Align.CENTER):style(th.pick.inactive)
      footer = "Please wait"
    elseif #state.matches == 0 then
      lines[1] = ui.Line("No matching directories"):align(ui.Align.CENTER):style(th.pick.inactive)
      footer = "Enter a different search · Ctrl-C cancels"
    else
      local rows = math.max(1, list_area.h)
      local cursor = math.max(1, math.min(state.cursor, #state.matches))
      local first = math.floor((cursor - 1) / rows) * rows + 1
      local last = math.min(#state.matches, first + rows - 1)

      for i = first, last do
        local active = i == cursor
        lines[#lines + 1] = ui.Line {
          ui.Span(active and "› " or "  "),
          ui.Span(display_path(state.matches[i])),
        }:style(active and th.pick.active or th.pick.inactive)
      end

      footer = string.format(
        "%d match%s · ↑/↓ choose · Enter select · Ctrl-C cancels",
        state.match_count,
        state.match_count == 1 and "" or "es"
      )
    end

    return {
      ui.Clear(area),
      ui.Border(ui.Edge.ALL):area(area):type(ui.Border.ROUNDED):style(th.pick.border),
      ui.List(lines):area(list_area),
      ui.Line(" Matches "):area(title_area):style(th.pick.border),
      ui.Line(footer):area(footer_area):style(th.pick.inactive):dim(),
    }
  end

  state.modal_id = Modal:children_add(Popup, 1500)
end

local popup_visible = ya.sync(function(state)
  return state.visible == true
end)

local show_loading = ya.sync(function(state)
  state.visible = true
  state.matches = {}
  state.cursor = 0
  state.match_count = 0
  state.message = "Looking for folders…"
  ui.render()
end)

local show_matches = ya.sync(function(state, matches, match_count)
  state.visible = true
  state.matches = matches
  state.cursor = #matches > 0 and 1 or 0
  state.match_count = match_count
  state.message = nil
  ui.render()
end)

local hide_popup = ya.sync(function(state)
  state.visible = false
  state.matches = {}
  state.cursor = 0
  state.match_count = 0
  state.message = nil
  ui.render()
end)

local move_popup = ya.sync(function(state, step)
  if not state.visible or state.message or #state.matches == 0 then
    return false
  end

  state.cursor = ((state.cursor - 1 + step) % #state.matches) + 1
  ui.render()
  return true
end)

local selected_destination = ya.sync(function(state)
  if not state.visible or state.cursor < 1 then
    return nil
  end
  return state.matches[state.cursor]
end)

local get_cached_directories = ya.sync(function(state, home, now)
  if state.directory_cache_home ~= home or not state.directory_cache_until or now >= state.directory_cache_until then
    return nil
  end
  return state.directory_cache
end)

local cache_directories = ya.sync(function(state, home, directories, expires_at)
  state.directory_cache_home = home
  state.directory_cache = directories
  state.directory_cache_until = expires_at
end)

local function scan_directories(home)
  local output, err = Command("fd")
    :arg({ "--type", "d", "--absolute-path", "--print0", "--no-ignore", ".", home })
    :output()

  if not output then
    return nil, "Could not scan folders: " .. tostring(err or "unknown error")
  end

  local directories = { home }
  local seen = { [home] = true }
  local found = 0
  for path in output.stdout:gmatch("([^%z]+)%z") do
    local normalized = path
    if #normalized > 1 then
      normalized = normalized:gsub("/+$", "")
    end
    if not seen[normalized] then
      directories[#directories + 1] = normalized
      seen[normalized] = true
      found = found + 1
    end
  end

  if not output.status.success and found == 0 then
    local detail = output.stderr:gsub("%s+$", "")
    if detail == "" then
      detail = "fd could not read the folder tree"
    end
    return nil, "Could not scan folders: " .. detail
  end

  return directories
end

local function token_score(text, token)
  local score = 0
  local exact = text:find(token, 1, true)
  if exact then
    score = score + 120 + (#token * 8) - exact
  end

  local basename = text:match("([^/]+)$") or text
  local basename_exact = basename:find(token, 1, true)
  if basename_exact then
    score = score + 90 - basename_exact
  end

  local previous = 0
  local consecutive = 0
  for i = 1, #token do
    local found = text:find(token:sub(i, i), previous + 1, true)
    if not found then
      return nil
    end

    local gap = found - previous - 1
    if found == previous + 1 then
      consecutive = consecutive + 1
      score = score + 12 + consecutive * 3
    else
      consecutive = 0
      score = score - math.min(gap, 12)
    end

    local before = found > 1 and text:sub(found - 1, found - 1) or ""
    if found == 1 or before == "/" or before == "_" or before == "-" or before == "." or before == " " then
      score = score + 14
    end
    previous = found
  end

  return score
end

local function filter_directories(directories, query)
  local tokens = {}
  for token in query:lower():gmatch("%S+") do
    tokens[#tokens + 1] = token
  end

  if #tokens == 0 then
    local matches = {}
    for i = 1, math.min(#directories, MAX_MATCHES) do
      matches[i] = directories[i]
    end
    return matches, #directories
  end

  local ranked = {}
  for _, path in ipairs(directories) do
    local shown = display_path(path)
    local lowered = shown:lower()
    local score = 0
    local matched = true

    for _, token in ipairs(tokens) do
      local part = token_score(lowered, token)
      if not part then
        matched = false
        break
      end
      score = score + part
    end

    if matched then
      ranked[#ranked + 1] = {
        path = path,
        shown = shown,
        score = score - (#lowered * 0.05),
      }
    end
  end

  table.sort(ranked, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    elseif #a.shown ~= #b.shown then
      return #a.shown < #b.shown
    end
    return a.shown < b.shown
  end)

  local matches = {}
  for i = 1, math.min(#ranked, MAX_MATCHES) do
    matches[i] = ranked[i].path
  end
  return matches, #ranked
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

local function choose_destination(directories)
  local query = ""
  local matches, match_count = filter_directories(directories, query)
  show_matches(matches, match_count)

  local input = ya.input {
    pos = { "center", y = -7, w = 72 },
    title = " Move destination · type to filter ",
    value = "",
    realtime = true,
    debounce = 0.05,
  }

  while true do
    local value, event = input:recv()
    value = value or ""

    if event == 3 then
      query = value
      matches, match_count = filter_directories(directories, query)
      show_matches(matches, match_count)
    elseif event == 1 then
      -- Enter can arrive before the final debounced change event.
      if value ~= query then
        matches, match_count = filter_directories(directories, value)
        show_matches(matches, match_count)
      end
      local destination = selected_destination()
      hide_popup()
      return destination
    elseif event == 2 then
      hide_popup()
      return nil
    else
      hide_popup()
      return nil, "Destination input closed unexpectedly"
    end
  end
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
  setup = setup,

  entry = function(_, job)
    local raw_step = job and job.args and job.args.move
    local step = raw_step and tonumber(tostring(raw_step)) or nil
    if step then
      move_popup(step)
      return
    elseif popup_visible() then
      return
    end

    local files = get_files()
    if #files == 0 then
      ya.notify({ title = "Moveto", content = "No files selected or hovered.", level = "warn", timeout = 3 })
      return
    end

    local home = os.getenv("HOME")
    if not home then
      ya.notify({ title = "Move picker error", content = "HOME is not set", level = "error", timeout = 5 })
      return
    end

    local now = os.time()
    local directories = get_cached_directories(home, now)
    if not directories then
      show_loading()
      local scan_err
      directories, scan_err = scan_directories(home)
      if not directories then
        hide_popup()
        ya.notify({ title = "Move picker error", content = tostring(scan_err), level = "error", timeout = 5 })
        return
      end
      cache_directories(home, directories, now + CACHE_SECONDS)
    end

    local ok, dest, picker_err = pcall(choose_destination, directories)
    if not ok then
      hide_popup()
      picker_err = dest
      dest = nil
    end

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
