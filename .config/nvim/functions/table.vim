" ============================================================
" table.vim — Markdown / CSV → LaTeX or Markdown table
" Source from init.vim with:
"   source ~/.config/nvim/functions/table.vim
" ============================================================

" ── Cell sanitizer ───────────────────────────────────────────────────────────
function! s:SanitizeCell(cell)
  let l:c = a:cell
  let l:umap = {
    \ '⁰':'0','¹':'1','²':'2','³':'3','⁴':'4',
    \ '⁵':'5','⁶':'6','⁷':'7','⁸':'8','⁹':'9'
    \ }
  for [l:uni, l:num] in items(l:umap)
    let l:c = substitute(l:c, l:uni, l:num, 'g')
  endfor
  let l:c = substitute(l:c, '\^{\([^}]*\)}', '\\textsuperscript{\1}', 'g')
  let l:c = substitute(l:c, '\^\([0-9a-zA-Z+\-][0-9]*\)', '\\textsuperscript{\1}', 'g')
  return l:c
endfunction

" ── Quote-aware CSV splitter ─────────────────────────────────────────────────
function! s:SplitRespectingQuotes(line, delim)
  let result = []
  let current = ''
  let in_quotes = 0
  let i = 0
  while i < len(a:line)
    let ch = a:line[i]
    if ch == '"'
      let in_quotes = !in_quotes
    elseif ch == a:delim && !in_quotes
      call add(result, trim(current))
      let current = ''
      let i += 1
      continue
    else
      let current .= ch
    endif
    let i += 1
  endwhile
  call add(result, trim(current))
  return result
endfunction

" ── Pipe row splitter ────────────────────────────────────────────────────────
function! s:SplitPipeRow(line)
  let l:stripped = substitute(a:line, '^\s*|\(.*\)|\s*$', '\1', '')
  let l:cells = split(l:stripped, '|')
  return map(l:cells, 'trim(v:val)')
endfunction

" ── Pipe table detector ──────────────────────────────────────────────────────
function! s:IsPipeTable(lines)
  if empty(a:lines) || a:lines[0] !~ '^\s*|' || len(a:lines) < 2
    return 0
  endif
  return a:lines[1] =~ '^\s*|[-| :]*|'
endfunction

" ── Pipe table parser ────────────────────────────────────────────────────────
function! s:ParsePipeTable(lines)
  let l:headers = s:SplitPipeRow(a:lines[0])
  let l:data_rows = []
  for l:row in a:lines[2:]
    if l:row =~ '^\s*|'
      call add(l:data_rows, l:row)
    endif
  endfor
  return [l:headers, l:data_rows]
endfunction

" ── Optionally wrap tabular block with \resizebox ─────────────────────────────
" scale=1 → \resizebox{\linewidth}{!}{...}   (forces full page width)
" scale=0 → no wrapper                        (natural size, default)
function! s:WrapTabular(inner_lines, scale)
  if a:scale
    return ['\resizebox{\linewidth}{!}{%'] + a:inner_lines + ['}']
  else
    return a:inner_lines
  endif
endfunction

" ── Ask user whether to force full-width scaling ─────────────────────────────
function! s:AskScale()
  let ans = input("Force full page width? (y/N): ")
  return ans =~? '^y'
endfunction

" ── LaTeX output builder ─────────────────────────────────────────────────────
function! s:BuildLatex(headers, data_rows, num_cols, caption, label, is_pipe, scale)
  let inner = ['\begin{tabular}{l' . repeat('c', a:num_cols - 1) . '}']
  let header_cells = map(copy(a:headers), '"\\textbf{" . escape(s:SanitizeCell(trim(v:val)), "&%#") . "}"')
  call add(inner, '\toprule')
  call add(inner, join(header_cells, ' & ') . ' \\')
  call add(inner, '\midrule')
  for row in a:data_rows
    if a:is_pipe
      let cells = s:SplitPipeRow(row)
    else
      let cells = s:SplitRespectingQuotes(row, ',')
    endif
    let row_cells = map(range(a:num_cols), 'v:val < len(cells) ? escape(s:SanitizeCell(trim(cells[v:val])), "&%#") : ""')
    call add(inner, join(row_cells, ' & ') . ' \\')
  endfor
  call add(inner, '\bottomrule')
  call add(inner, '\end{tabular}')

  let latex = [
    \ '\begin{table}[H]',
    \ '\centering',
    \ '\caption{' . a:caption . '}',
    \ '\label{' . a:label . '}',
    \ ]
  let latex += s:WrapTabular(inner, a:scale)
  call add(latex, '\end{table}')
  return latex
endfunction

" ── Main Table function ──────────────────────────────────────────────────────
function! Table() range
  let lines = getline(a:firstline, a:lastline)
  if empty(lines)
    echom "No lines selected"
    return
  endif

  " ── PIPE TABLE PATH ───────────────────────────────────────────────────────
  if s:IsPipeTable(lines)
    let [l:headers, l:data_rows] = s:ParsePipeTable(lines)
    let l:num_cols = len(l:headers)
    if l:num_cols == 0
      echom "Error: No columns detected in pipe table"
      return
    endif
    let mode_choice = input("Pipe table detected. Output (l)aTeX or (m)arkdown [default l]: ")
    if empty(mode_choice) | let mode_choice = 'l' | endif

    if mode_choice =~? 'm'
      let md = []
      call add(md, '| ' . join(l:headers, ' | ') . ' |')
      call add(md, '|' . repeat('---|', l:num_cols))
      for row in l:data_rows
        let cells = s:SplitPipeRow(row)
        let row_cells = map(range(l:num_cols), 'v:val < len(cells) ? cells[v:val] : ""')
        call add(md, '| ' . join(row_cells, ' | ') . ' |')
      endfor
      execute a:firstline . ',' . a:lastline . 'delete _'
      call append(a:firstline - 1, md)
      return
    endif

    let caption = input('Enter caption: ', 'Table Caption')
    let label   = input('Enter label (e.g., tab:yourlabel): ', 'tab:yourlabel')
    let scale   = s:AskScale()
    let latex   = s:BuildLatex(l:headers, l:data_rows, l:num_cols, caption, label, 1, scale)
    execute a:firstline . ',' . a:lastline . 'delete _'
    call append(a:firstline - 1, latex)
    return
  endif

  " ── CSV / MANUAL INPUT PATH ───────────────────────────────────────────────
  let mode_choice = input("Output mode (l)aTeX or (m)arkdown [default l]: ")
  if empty(mode_choice) | let mode_choice = 'l' | endif
  if mode_choice !~ '^[lmLM]$'
    echom "Invalid mode. Use l or m."
    return
  endif
  let use_markdown = (mode_choice =~? 'm')

  let delimiter = input("Enter the delimiter (default is ','): ")
  if empty(delimiter) | let delimiter = ',' | endif

  let num_header_lines = input("Enter the number of header lines (0, 1, or 2): ")
  if num_header_lines !~ '^[0-2]$'
    echom "Invalid input. Please enter 0, 1, or 2."
    return
  endif
  let num_header_lines = str2nr(num_header_lines)

  if num_header_lines == 0
    let header_input = input("Enter headers separated by commas: ")
    let headers   = s:SplitRespectingQuotes(header_input, delimiter)
    let data_rows = lines
  elseif num_header_lines == 1
    if len(lines) < 1 | echom "Error: Not enough lines selected" | return | endif
    let headers   = s:SplitRespectingQuotes(lines[0], delimiter)
    let data_rows = lines[1:]
  elseif num_header_lines == 2
    if len(lines) < 2 | echom "Error: Not enough lines selected for composite headers" | return | endif
    let group_headers = s:SplitRespectingQuotes(lines[0], delimiter)
    let subheaders    = s:SplitRespectingQuotes(lines[1], delimiter)
    let data_rows     = lines[2:]
    let group_names   = filter(copy(group_headers[1:]), '!empty(v:val)')
    let num_groups    = len(group_names)
    if num_groups == 0 | echom "Error: No group headers found" | return | endif
    let num_subheaders = len(subheaders) - 1
    if num_subheaders <= 0 | echom "Error: Not enough subheaders" | return | endif
    if num_subheaders % num_groups != 0
      echom "Error: Subheaders (" . num_subheaders . ") not divisible by groups (" . num_groups . ")"
      return
    endif
    let span = num_subheaders / num_groups
  endif

  let num_cols = (num_header_lines == 2) ? len(subheaders) : len(headers)
  if num_cols == 0 | echom "Error: No columns detected" | return | endif

  " ── MARKDOWN OUTPUT ───────────────────────────────────────────────────────
  if use_markdown
    let md = []
    if num_header_lines == 2
      call add(md, '<!-- Composite header: ' . join(group_names, ', ') . ' -->')
      call add(md, '| ' . join(subheaders, ' | ') . ' |')
    else
      call add(md, '| ' . join(headers, ' | ') . ' |')
    endif
    call add(md, '|' . repeat('---|', num_cols))
    for row in data_rows
      let cells     = s:SplitRespectingQuotes(row, delimiter)
      let row_cells = map(range(num_cols), 'v:val < len(cells) ? cells[v:val] : ""')
      call add(md, '| ' . join(row_cells, ' | ') . ' |')
    endfor
    execute a:firstline . ',' . a:lastline . 'delete _'
    call append(a:firstline - 1, md)
    return
  endif

  " ── LATEX OUTPUT ──────────────────────────────────────────────────────────
  let caption = input('Enter caption: ', 'Table Caption')
  let label   = input('Enter label (e.g., tab:yourlabel): ', 'tab:yourlabel')
  let scale   = s:AskScale()

  if num_header_lines == 2
    let inner = ['\begin{tabular}{l' . repeat('c', num_cols - 1) . '}']
    let group_row = ['']
    for i in range(num_groups)
      call add(group_row, '\multicolumn{' . span . '}{c}{\textbf{' . escape(s:SanitizeCell(group_names[i]), "&%#") . '}}')
    endfor
    call add(inner, '\toprule')
    call add(inner, join(group_row, ' & ') . ' \\')
    let cmidrules = []
    for i in range(num_groups)
      let start_col = 2 + i * span
      let end_col   = start_col + span - 1
      call add(cmidrules, '\cmidrule(lr){' . start_col . '-' . end_col . '}')
    endfor
    call add(inner, join(cmidrules, ' '))
    let subheader_cells = map(subheaders, '"\\textbf{" . escape(s:SanitizeCell(trim(v:val)), "&%#") . "}"')
    call add(inner, join(subheader_cells, ' & ') . ' \\')
    call add(inner, '\midrule')
    for row in data_rows
      let cells     = s:SplitRespectingQuotes(row, delimiter)
      let row_cells = map(range(num_cols), 'v:val < len(cells) ? escape(s:SanitizeCell(trim(cells[v:val])), "&%#") : ""')
      call add(inner, join(row_cells, ' & ') . ' \\')
    endfor
    call add(inner, '\bottomrule')
    call add(inner, '\end{tabular}')

    let latex = [
      \ '\begin{table}[H]',
      \ '\centering',
      \ '\caption{' . caption . '}',
      \ '\label{' . label . '}',
      \ ]
    let latex += s:WrapTabular(inner, scale)
    call add(latex, '\end{table}')
  else
    let latex = s:BuildLatex(headers, data_rows, num_cols, caption, label, 0, scale)
  endif

  execute a:firstline . ',' . a:lastline . 'delete _'
  call append(a:firstline - 1, latex)
endfunction

command! -range Table <line1>,<line2>call Table()
vnoremap <leader>t :Table<CR>
