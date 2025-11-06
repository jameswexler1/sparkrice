-- diary.lua: Pandoc filter to process diary entries

local function escape_latex(str)
  local replacements = {
    ['\\'] = '\\textbackslash{}',
    ['&'] = '\\&',
    ['%'] = '\\%',
    ['$'] = '\\$',
    ['#'] = '\\#',
    ['_'] = '\\_',
    ['{'] = '\\{',
    ['}'] = '\\}',
    ['~'] = '\\textasciitilde{}',
    ['^'] = '\\textasciicircum{}',
  }
  return (str:gsub('.', function(c) return replacements[c] or c end))
end

local function is_date(lower_text)
  if lower_text:match('^%s*%d%d?%s+de%s+[a-zA-ZçÇ]+%s+de%s+%d%d%d%d%s*(%b())?%s*$') then return true end
  if lower_text:match('^%s*[a-zA-ZçÇ]+%s+%d%d?,%s+%d%d%d%d%s*$') then return true end
  if lower_text:match('^%s*%d%d?%s+[a-zA-ZçÇ]+%s+%d%d%d%d%s*$') then return true end
  return false
end

function Pandoc(doc)
  local new_blocks = {}
  local dates = {}
  local current_content = {}
  local in_entry = false

  for _, block in ipairs(doc.blocks) do
    local tag = block.tag
    if tag == 'Header' or tag == 'Para' or tag == 'Plain' then
      local text = pandoc.utils.stringify(block)
      text = text:gsub('^%s*#%s*', '')
      local lower_text = text:lower()

      if is_date(lower_text) then
        -- Finish previous entry if exists
        if in_entry then
          local content_str = ""
          for i, content_block in ipairs(current_content) do
            if i > 1 then
              content_str = content_str .. "\n\n"
            end
            content_str = content_str .. pandoc.utils.stringify(content_block)
          end
          content_str = escape_latex(content_str)
          local date_escaped = escape_latex(dates[#dates])
          table.insert(new_blocks, pandoc.RawBlock('latex', '\\diaryentry{' .. date_escaped .. '}{' .. content_str .. '}'))
          current_content = {}
        end

        -- Start new entry
        table.insert(dates, text)
        in_entry = true
      else
        -- Add to current entry content
        if in_entry then
          table.insert(current_content, block)
        else
          table.insert(new_blocks, block)
        end
      end
    else
      -- Non-para/header blocks
        if in_entry then
          table.insert(current_content, block)
        else
          table.insert(new_blocks, block)
        end
      end
  end

  -- Add last entry
  if in_entry then
    local content_str = ""
    for i, content_block in ipairs(current_content) do
      if i > 1 then
        content_str = content_str .. "\n\n"
      end
      content_str = content_str + pandoc.utils.stringify(content_block)
    end
    content_str = escape_latex(content_str)
    local date_escaped = escape_latex(dates[#dates])
    table.insert(new_blocks, pandoc.RawBlock('latex', '\\diaryentry{' .. date_escaped .. '}{' .. content_str .. '}'))
  end

  -- Compute title and year if dates present
  if #dates > 0 then
    local month_translation = {
      ["janeiro"] = "Janeiro",
      ["fevereiro"] = "Fevereiro",
      ["março"] = "Março",
      ["abril"] = "Abril",
      ["maio"] = "Maio",
      ["junho"] = "Junho",
      ["julho"] = "Julho",
      ["agosto"] = "Agosto",
      ["setembro"] = "Setembro",
      ["outubro"] = "Outubro",
      ["novembro"] = "Novembro",
      ["dezembro"] = "Dezembro",
      ["january"] = "January",
      ["february"] = "February",
      ["march"] = "March",
      ["april"] = "April",
      ["may"] = "May",
      ["june"] = "June",
      ["july"] = "July",
      ["august"] = "August",
      ["september"] = "September",
      ["october"] = "October",
      ["november"] = "November",
      ["december"] = "December"
    }

    local first_date = dates[1]:lower()
    local last_date = dates[#dates]:lower()

    local first_month_lower = first_date:match('de%s+([a-zA-ZçÇ]+)%s+de') or first_date:match('^%s*([a-zA-ZçÇ]+)%s+%d') or first_date:match('%d%d?%s+([a-zA-ZçÇ]+)%s+%d')
    local last_month_lower = last_date:match('de%s+([a-zA-ZçÇ]+)%s+de') or last_date:match('^%s*([a-zA-ZçÇ]+)%s+%d') or last_date:match('%d%d?%s+([a-zA-ZçÇ]+)%s+%d')
    local year = first_date:match('%d%d%d%d')

    local cap_first = month_translation[first_month_lower] or (first_month_lower:sub(1,1):upper() .. first_month_lower:sub(2))
    local cap_last = month_translation[last_month_lower] or (last_month_lower:sub(1,1):upper() .. last_month_lower:sub(2))

    doc.meta.title = pandoc.MetaString('Diário ' .. cap_first .. ' - ' .. cap_last .. ' ' .. year)
    doc.meta.year = pandoc.MetaString(year)
  end

  doc.blocks = new_blocks
  return doc
end
