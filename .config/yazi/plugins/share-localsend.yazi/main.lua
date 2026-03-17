--- @sync entry
return {
    entry = function()
        -- Collect URLs from selected files (or hovered as fallback)
        local selected_urls = {}
        local selected_table = cx.active.selected
        if #selected_table > 0 then
            for _, f in pairs(selected_table) do
                table.insert(selected_urls, f)
            end
        else
            local hovered = cx.active.current.hovered
            if hovered and hovered.url then
                table.insert(selected_urls, hovered.url)
            end
        end
        -- Build safe shell-quoted argument string
        local files = {}
        for _, url in ipairs(selected_urls) do
            table.insert(files, ya.quote(tostring(url)))
        end
        local file_str = table.concat(files, " ")
        -- Full shell command (same as before)
        local cmd = string.format([[
            center_window() {
              sleep 0.3
              sw=$(xdpyinfo | grep dimensions | awk '{print $2}' | cut -d'x' -f1)
              sh=$(xdpyinfo | grep dimensions | awk '{print $2}' | cut -d'x' -f2)
              ww=370
              wh=480
              x=$((sw / 2 - ww / 2))
              y=$((sh / 2 - wh / 2))
              wid=$(xdotool search --onlyvisible --class "Localsend" 2>/dev/null | head -n1)
              if [ -n "$wid" ]; then
                xdotool windowsize "$wid" $ww $wh
                xdotool windowmove "$wid" $x $y
              fi
            }
            nohup localsend %s </dev/null >/dev/null 2>&1 & disown
            center_window &
        ]], file_str)
        os.execute(cmd)
    end,
}
