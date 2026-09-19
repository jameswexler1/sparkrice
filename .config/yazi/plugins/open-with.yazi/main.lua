--- @sync entry
-- The menu is rendered inside Yazi. A zero-size native confirmation owns the
-- input layer for the entire menu lifetime; navigation handlers run synchronously
-- so consecutive keys cannot slip through to the manager between awaits.
local M = {}

local function notify(message, level)
  ya.notify { title = "Open with", content = message, level = level or "error", timeout = 6 }
end

local function popup_area(state, available)
  if available.w < 8 or available.h < 4 then return nil end
  local current = ui.area("current")
  local folder = cx.active.current
  local width = math.min(state.width, available.w)
  local height = math.min(state.height, #state.items + 2, available.h)
  local x = math.max(available.x, math.min(current.x, available.x + available.w - width))
  local y = current.y + folder.cursor - folder.offset + 1
  if y + height > available.y + available.h then
    y = current.y + folder.cursor - folder.offset - height
  end
  y = math.max(available.y, math.min(y, available.y + available.h - height))
  return ui.Rect { x = x, y = y, w = width, h = height }
end

function M:setup(opts)
  if self.modal_id then return end
  opts = opts or {}
  self.width = math.max(8, opts.width or 50)
  self.height = math.max(3, opts.height or 7)
  self.items, self.cursor, self.first = {}, 1, 1
  self.visible, self.busy = false, false

  local state = self
  local Popup = { _id = "open-with-popup" }
  function Popup:new(area)
    return setmetatable({ _area = area }, { __index = self })
  end
  function Popup:reflow() return state.visible and { self } or {} end
  function Popup:redraw()
    if not state.visible then return {} end
    local area = popup_area(state, self._area)
    if not area then return {} end
    local rows = area.h - 2
    state.rows = rows
    state.first = math.max(1, math.min(state.first, #state.items - rows + 1))
    if state.cursor < state.first then state.first = state.cursor end
    if state.cursor >= state.first + rows then state.first = state.cursor - rows + 1 end

    local lines = {}
    for i = state.first, math.min(#state.items, state.first + rows - 1) do
      local active = i == state.cursor
      local label = ui.truncate(ui.printable(state.items[i]), { max = area.w - 4 })
      lines[#lines + 1] = ui.Line((active and " " or "  ") .. label)
        :style(active and th.pick.active or th.pick.inactive)
    end
    local widgets = {
      ui.Clear(area),
      ui.Border(ui.Edge.ALL):area(area):type(ui.Border.ROUNDED):style(th.pick.border),
      ui.Line(" Open with: "):area(ui.Rect {
        x = area.x + 1, y = area.y, w = area.w - 2, h = 1,
      }):style(th.pick.border),
      ui.List(lines):area(ui.Rect {
        x = area.x + 1, y = area.y + 1, w = area.w - 2, h = rows,
      }),
    }
    if #state.items > rows then
      local position = math.floor((state.cursor - 1) * (rows - 1) / (#state.items - 1))
      widgets[#widgets + 1] = ui.Line("█"):area(ui.Rect {
        x = area.x + area.w - 1, y = area.y + 1 + position, w = 1, h = 1,
      }):style(th.pick.border)
    end
    return widgets
  end
  self.modal_id = Modal:children_add(Popup, 1600)
end

local begin = ya.sync(function(state)
  if state.busy then return nil end
  local h = cx.active.current.hovered
  if not h then return nil, "No file is highlighted." end
  if not (h.url.spec.is_regular or h.url.spec.is_search) then
    return nil, "Download this remote file before opening it with a local application."
  end
  state.busy = true
  return tostring(h.url.path)
end)

local show = ya.sync(function(state, labels, path)
  local h = cx.active.current.hovered
  -- Discovery is asynchronous: don't pop up over a different file or tab.
  if not h or tostring(h.url.path) ~= path then return false end
  state.items, state.cursor, state.first = labels, 1, 1
  state.visible = true
  ui.render()
  return true
end)

local move = ya.sync(function(state, action)
  local count = #state.items
  if action == "up" then state.cursor = (state.cursor - 2) % count + 1
  elseif action == "down" then state.cursor = state.cursor % count + 1
  elseif action == "top" then state.cursor = 1
  elseif action == "bottom" then state.cursor = count
  elseif action == "page-up" then state.cursor = math.max(1, state.cursor - (state.rows or 5))
  elseif action == "page-down" then state.cursor = math.min(count, state.cursor + (state.rows or 5)) end
  ui.render()
end)

local selection = ya.sync(function(state) return state.cursor end)
local finish = ya.sync(function(state)
  state.visible, state.busy = false, false
  state.items = {}
  ui.render()
end)

local function helper_path()
  local config = os.getenv("YAZI_CONFIG_HOME")
  if not config or config == "" then
    local xdg = os.getenv("XDG_CONFIG_HOME")
    config = (xdg and xdg ~= "" and xdg or os.getenv("HOME") .. "/.config") .. "/yazi"
  end
  return config .. "/plugins/open-with.yazi/apps.pl"
end

local function choose(path, helper)
  local output, err = Command("perl"):arg { helper, "list", path }:output()
  if not output then error("Could not look up applications: " .. tostring(err)) end
  if not output.status.success then
    error(output.stderr:match("^%s*(.-)%s*$") or "Application lookup failed.")
  end
  local data, decode_err = ya.json_decode(output.stdout)
  if not data or type(data.apps) ~= "table" then
    error("Could not read the application list: " .. tostring(decode_err))
  end
  if #data.apps == 0 then
    notify("No applications are registered for " .. (data.mime or "this file type") .. ".", "warn")
    return
  end

  local labels = {}
  for _, app in ipairs(data.apps) do labels[#labels + 1] = app.name .. "  (" .. app.id .. ")" end
  if not show(labels, path) then return end
  local accepted = ya.confirm {
    title = "", body = "", pos = { "center", w = 0, h = 0 },
  }
  if accepted then return data.apps[selection()].desktop end
end

function M:entry(job)
  local action = job and job.args and job.args[1]
  if action then
    if self.visible then
      if action == "cancel" then
        ya.emit("confirm:close", {})
      elseif action ~= "yes" then
        move(action)
      end
    elseif action == "up" or action == "down" then
      -- Preserve ordinary confirmation dialogs, including copy/move plugins.
      ya.emit("confirm:arrow", { action == "up" and "prev" or "next" })
    elseif action == "yes" then
      ya.emit("confirm:close", { submit = true })
    end
    return
  end

  local path, problem = begin()
  if not path then
    if problem then notify(problem, "warn") end
    return
  end
  local helper = helper_path()
  ya.async(function()
    local ok, desktop = pcall(choose, path, helper)
    finish()
    if not ok then
      notify(tostring(desktop))
    elseif desktop then
      -- Escape shell arguments and Yazi's separate percent-template expansion.
      local command = "perl " .. ya.quote(helper) .. " launch " .. ya.quote(desktop) .. " " .. ya.quote(path)
      ya.emit("shell", { command:gsub("%%", "%%%%"), orphan = true })
    end
  end)
end

return M
