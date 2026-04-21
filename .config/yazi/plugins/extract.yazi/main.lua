-- ~/.config/yazi/plugins/extract.yazi/main.lua

-- Safe logging: ya.dbg writes to ~/.local/state/yazi/yazi.log
-- and is safe to call from async context unlike io.open
local function log(msg)
  ya.dbg("extract.yazi: " .. msg)
end

-- ya.sync can only return PRIMITIVE types (strings, numbers, booleans).
-- Returning a Url object across the thread boundary silently breaks things.
-- Convert to string INSIDE the sync block.
local get_target = ya.sync(function()
  local tab = cx.active
  local hovered = tab.current.hovered

  local selected = tab.selected or {}
  local count = 0
  local selected_path = nil

  for u in pairs(selected) do
    count = count + 1
    if count > 1 then
      return nil, "multiple"
    end
    selected_path = tostring(u)  -- convert to string HERE, inside sync
  end

  if count == 1 then
    return selected_path, nil
  elseif hovered then
    return tostring(hovered.url), nil  -- string, not Url object
  else
    return nil, "none"
  end
end)

return {
  entry = function()
    log("triggered")

    local file, problem = get_target()

    if problem == "multiple" then
      ya.notify({ title = "Extract", content = "Select a single archive.", level = "warn", timeout = 5 })
      return
    elseif problem == "none" or not file then
      ya.notify({ title = "Extract", content = "No file selected or hovered.", level = "warn", timeout = 5 })
      return
    end

    local basename = file:match("([^/]+)$") or file
    log("target: " .. file)

    -- ya.confirm body must be ui.Text, not a plain string
    local confirmed = ya.confirm {
      pos   = { "center", w = 60, h = 10 },
      title = "Extract Archive",
      body  = ui.Text("Extract " .. basename .. "?"):wrap(ui.Wrap.YES),
    }
    if not confirmed then
      log("cancelled")
      return
    end

    local lower = basename:lower()

    -- ipairs preserves order: multi-extension patterns (.tar.gz) must
    -- come before their suffixes (.gz), or the wrong tool gets matched.
    local patterns = {
      { "%.tar%.bz2$",  "tar",       "xjf" },
      { "%.tbz2$",      "tar",       "xjf" },
      { "%.tar%.gz$",   "tar",       "xzf" },
      { "%.tgz$",       "tar",       "xzf" },
      { "%.tar%.xz$",   "tar",       "xJf" },
      { "%.txz$",       "tar",       "xJf" },
      { "%.tar$",       "tar",       "xf"  },
      { "%.zip$",       "unzip",     nil   },
      { "%.7z$",        "7z",        "x"   },
      { "%.rar$",       "unrar",     "e"   },
      { "%.bz2$",       "bunzip2",   nil   },
      { "%.gz$",        "gunzip",    nil   },
      { "%.xz$",        "xz",        "-d"  },
      { "%.z$",         "uncompress", nil  },
    }

    local prog, flag
    for _, pat in ipairs(patterns) do
      if lower:match(pat[1]) then
        prog = pat[2]
        flag = pat[3]
        break
      end
    end

    if not prog then
      ya.notify({ title = "Extract", content = "Unsupported format: " .. basename, level = "warn", timeout = 5 })
      log("unsupported: " .. basename)
      return
    end

    local args = {}
    if flag then args[#args + 1] = flag end
    args[#args + 1] = file

    log("exec: " .. prog .. " " .. table.concat(args, " "))

    -- stdout/stderr default to NULL; stdin NULL prevents interactive prompts.
    -- Use wait() not wait_with_output() — no output to capture, and piped
    -- buffers can fill and deadlock on large extractions.
    local child, spawn_err = Command(prog)
      :args(args)
      :stdin(Command.NULL)
      :stdout(Command.NULL)
      :stderr(Command.NULL)
      :spawn()

    if not child then
      ya.notify({
        title   = "Extract failed",
        content = prog .. " could not start. Is it installed?\n(" .. tostring(spawn_err) .. ")",
        level   = "error",
        timeout = 8,
      })
      log("spawn failed: " .. tostring(spawn_err))
      return
    end

    local status, wait_err = child:wait()

    if status and status.success then
      ya.notify({ title = "📂 Extracted", content = basename .. " extracted successfully.", level = "info", timeout = 5 })
      log("success")
    else
      local code = status and tostring(status.code) or tostring(wait_err)
      ya.notify({
        title   = "Extract failed",
        content = prog .. " exited with error " .. code .. ".\nSee terminal for details.",
        level   = "error",
        timeout = 8,
      })
      log("failed, code: " .. code)
    end
  end,
}
