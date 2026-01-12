
-- THIS SCRIPT IS A DEPENDENCY OF 3grav, used for subtitle recording

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local entries = {}
local subtitle_path = mp.command_native({"expand-path", "~~/output.srt"})  -- Change to desired path, e.g., "/tmp/output.srt"
local log_path = mp.command_native({"expand-path", "~~/subtitle_log.txt"})  -- Log file for errors/debug

-- Helper: Append to log file
local function log_to_file(text)
    local f = io.open(log_path, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. text .. "\n")
        f:close()
    end
end

-- Helper: Convert seconds to SRT timestamp (HH:MM:SS,mmm)
local function fmt_ts(sec)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = math.floor(sec % 60)
    local ms = math.floor((sec - math.floor(sec)) * 1000)
    return string.format("%02d:%02d:%02d,%03d", h, m, s, ms)
end

-- Store a new subtitle entry
local function store_entry(start_sec, text)
    if text and text ~= "" then
        table.insert(entries, {time = start_sec, text = text})
        mp.osd_message("Added subtitle at " .. fmt_ts(start_sec) .. ": " .. text, 2)
        log_to_file("Added entry: " .. text .. " at " .. start_sec)
    end
end

-- Save all entries to .srt file
local function save_srt()
    local success, err = pcall(function()
        local f = io.open(subtitle_path, "w")
        if not f then
            error("Could not open SRT file for writing")
        end
        for i, e in ipairs(entries) do
            local start = fmt_ts(e.time)
            local dur = 3.0  -- Default duration; adjust as needed (e.g., to 5.0 for longer display)
            local ending = fmt_ts(e.time + dur)
            f:write(i .. "\n" .. start .. " --> " .. ending .. "\n" .. e.text .. "\n\n")
        end
        f:close()
        mp.osd_message("SRT saved to " .. subtitle_path, 3)
        log_to_file("Saved SRT with " .. #entries .. " entries")
    end)
    if not success then
        mp.osd_message("Error saving SRT: " .. (err or "unknown"), 5)
        log_to_file("Error saving SRT: " .. (err or "unknown"))
    end
end

-- Function to get text input via dmenu
local function get_subtitle_text(callback)
    local was_paused = mp.get_property_bool("pause")
    mp.set_property_bool("pause", true)  -- Pause while inputting
    local res = mp.command_native({
        name = "subprocess",
        args = {"dmenu", "-p", "Enter subtitle text (empty to cancel):"},
        capture_stdout = true,
        capture_stderr = true
    })
    local text = res.stdout:gsub("\n$", "")  -- Trim newline
    if res.status ~= 0 then
        local err_msg = res.stderr or "dmenu failed"
        mp.osd_message("dmenu error: " .. err_msg, 5)
        log_to_file("dmenu error: " .. err_msg .. " (status: " .. res.status .. ")")
    elseif text ~= "" then
        callback(text)
    end
    mp.set_property_bool("pause", was_paused)  -- Resume if was playing
end

-- Key binding to add subtitle (press 'ctrl+a' for Add subtitle)
mp.add_key_binding("ctrl+a", "add-subtitle", function()
    local success, err = pcall(function()
        local ts = mp.get_property_number("time-pos")
        if ts then
            get_subtitle_text(function(text)
                store_entry(ts, text)
            end)
        else
            error("Could not get time-pos")
        end
    end)
    if not success then
        mp.osd_message("Error adding subtitle: " .. (err or "unknown"), 5)
        log_to_file("Error adding subtitle: " .. (err or "unknown"))
    end
end)

-- Key binding to save .srt (press 'CTRL+s')
mp.add_key_binding("CTRL+s", "save-srt", save_srt)

-- Auto-save on quit and log startup
mp.register_event("shutdown", save_srt)
log_to_file("Script started")
mp.osd_message("Subtitle script loaded. Press 'ctrl+a' to add sub, CTRL+S to save.", 3)
