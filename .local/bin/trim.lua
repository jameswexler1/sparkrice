local mp = require 'mp'
local opts = require 'mp.options'

local options = {}
opts.read_options(options, "trim")
local mode = options.trim_mode or "keep"
local seg_type = (mode == "remove") and "removal" or "segment"

local segments = {}
local current_a = nil
local current_b = nil

local function time_to_str(t)
    if not t then return "none" end
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = t % 60
    return string.format("%02d:%02d:%06.3f", h, m, s)
end

local function set_a()
    current_a = mp.get_property_number("time-pos")
    mp.osd_message("A set: " .. time_to_str(current_a))
end

local function set_b()
    current_b = mp.get_property_number("time-pos")
    mp.osd_message("B set: " .. time_to_str(current_b))
end

local function add_segment()
    if current_a and current_b and current_a < current_b then
        table.insert(segments, {start = current_a, end_ = current_b})
        mp.osd_message("Added " .. seg_type .. ": " .. time_to_str(current_a) .. " - " .. time_to_str(current_b) .. " (#" .. #segments .. ")")
        current_a = nil
        current_b = nil
    else
        mp.osd_message("Invalid A/B (A must be before B)")
    end
end

local function save_segments()
    if #segments == 0 then
        mp.osd_message("No segments to save")
        return
    end
    table.sort(segments, function(a, b) return a.start < b.start end)
    local file_path = os.getenv("HOME") .. "/.config/mpv/trim_segments.txt"
    local file = io.open(file_path, "w")
    if file then
        for _, seg in ipairs(segments) do
            file:write(string.format("%.3f %.3f\n", seg.start, seg.end_))
        end
        file:close()
        mp.osd_message("Segments saved to " .. file_path)
        mp.commandv("quit")  -- Exit mpv after saving
    else
        mp.osd_message("Failed to save segments")
    end
end

mp.add_key_binding("a", "set_a", set_a)
mp.add_key_binding("b", "set_b", set_b)
mp.add_key_binding("s", "add_segment", add_segment)
mp.add_key_binding("ctrl+s", "save_segments", save_segments)
