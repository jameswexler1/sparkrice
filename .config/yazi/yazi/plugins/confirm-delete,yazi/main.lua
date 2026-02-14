local function entry()
	local selected = cx.active.selected
	if #selected == 0 then
		local hovered = cx.active.current.hovered
		if hovered then
			selected = { hovered.url }
		else
			ya.notify { title = "Delete", content = "No files selected or hovered.", level = "warn" }
			return
		end
	end

	local input = ya.input {
		title = "Confirm Delete (type 'y' and press Enter)",
		position = { "center", w = 50, h = 5 },
	}

	if input == nil then
		return  -- Canceled (e.g., Esc)
	end

	-- Trim whitespace and make case-insensitive
	local confirmed = input:gsub("^%s*(.-)%s*$", "%1"):lower()

	if confirmed == "y" then
		ya.manager_emit("remove", { permanently = false })  -- Trash, not permanent delete
	else
		ya.notify { title = "Delete", content = "Deletion canceled.", level = "info" }
	end
end

return { entry = entry }
