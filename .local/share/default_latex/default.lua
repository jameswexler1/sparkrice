-- default.lua — pandoc Lua filter for image placement
-- Place at: ~/.local/share/default_latex/default.lua
-- Automatically used by CompileAndClean when compiling with default.tex

function Para(el)
  -- Only intercept paragraphs that contain a single image
  if #el.content == 1 and el.content[1].t == "Image" then
    local img = el.content[1]

    -- Read width attribute, default to 80% of line width
    local width = img.attributes["width"] or "0.8\\linewidth"

    -- If width is a percentage like "60%", convert to LaTeX fraction
    local pct = width:match("^(%d+)%%$")
    if pct then
      width = string.format("%.2f\\linewidth", tonumber(pct) / 100)
    end

    -- Stringify caption (empty string if none)
    local caption = pandoc.utils.stringify(img.caption)

    -- Resolve path: expand ~ to $HOME if present
    local src = img.src:gsub("^~/", os.getenv("HOME") .. "/")

    -- Build the LaTeX figure block
    local latex = "\\begin{figure}[H]\n\\centering\n"
    latex = latex .. string.format("\\includegraphics[width=%s]{%s}\n", width, src)
    if caption ~= "" then
      latex = latex .. string.format("\\caption{%s}\n", caption)
    end
    latex = latex .. "\\end{figure}"

    return pandoc.RawBlock("latex", latex)
  end
end
