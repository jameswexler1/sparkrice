-- Add mtime to the right side of the status bar
Status:children_add(function()
    local h = cx.active.current.hovered
    if h then
        return ui.Line {
            ui.Span(os.date("%a %b %d %H:%M:%S %Y", math.floor(h.cha.mtime or 0))),
            ui.Span(" "),
        }
    end
    return ui.Line {}
end, 500, Status.RIGHT)
