let mapleader =","

if ! filereadable(system('echo -n "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/autoload/plug.vim"'))
    echo "Downloading junegunn/vim-plug to manage plugins..."
    silent !mkdir -p ${XDG_CONFIG_HOME:-$HOME/.config}/nvim/autoload/
    silent !curl "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" > ${XDG_CONFIG_HOME:-$HOME/.config}/nvim/autoload/plug.vim
    autocmd VimEnter * PlugInstall
endif

call plug#begin(system('echo -n "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/plugged"'))
Plug 'tpope/vim-surround'
Plug 'preservim/nerdtree'
Plug 'ryanoasis/vim-devicons'          " still needed for NERDTree icons
Plug 'nvim-tree/nvim-web-devicons'     " ← new: modern icons for lualine
Plug 'junegunn/goyo.vim'
Plug 'jreybert/vimagit'
Plug 'vimwiki/vimwiki'
Plug 'nvim-lualine/lualine.nvim'       " ← NEW: replaces vim-airline completely
Plug 'tpope/vim-commentary'
Plug 'ap/vim-css-color'
call plug#end()

" === Modern lualine statusbar (pywal + lines + orange + wordcount + NO git branch + ABSOLUTE path) ===
lua << EOF
-- Custom functions
local function total_lines()
  return vim.fn.line('.') .. '/' .. vim.fn.line('$')   -- "42/1234"
end

local function wordcount()
  local ext = vim.fn.expand('%:e'):lower()
  local ft  = vim.bo.filetype
  if ext == 'txt' or ext == 'md' or ft == 'markdown' or ft == 'txt' or ft == 'text' then
    return vim.fn.wordcount().words .. ' words'
  end
  return ''
end

local show_undo_info = false
local function undo_info()
  if not show_undo_info then return '' end
  local ut = vim.fn.undotree()
  local entries = ut.entries
  if vim.tbl_isempty(entries) then return '' end
  local seq_cur = ut.seq_cur
  local seq_last = ut.seq_last
  local timestamp = nil
  for _, e in ipairs(entries) do
    if e.seq == seq_cur then
      timestamp = e.time
      break
    end
  end
  if not timestamp then return '' end
  local date = os.date('%Y-%m-%d %H:%M', timestamp)
  local steps = seq_last - seq_cur
  if steps == 0 then
    return '⏱ ' .. date .. ' [latest]'
  else
    return '⏱ ' .. date .. ' [-' .. steps .. ']'
  end
end

vim.keymap.set('n', '<leader>u', function()
  show_undo_info = not show_undo_info
end, { desc = 'Toggle undo info' })

require('lualine').setup({
  options = {
    icons_enabled = true,
    theme = 'pywal',
    component_separators = { left = '', right = '' },
    section_separators = { left = '', right = '' },
    disabled_filetypes = { 'NERDTree' },
    always_divide_middle = true,
    globalstatus = false,
  },
  sections = {
    lualine_a = {{
      'mode',
      color = function()
        if vim.bo.modified then
          return { fg = '#1e1e2e', bg = '#ff8800', gui = 'bold' }  -- orange on modified
        end
      end,
    }},
    lualine_b = { 'diff', 'diagnostics' },          -- ← git BRANCH completely removed
    lualine_c = {{
      'filename',
      path = 2,                                     -- ← ABSOLUTE path (what you asked for)
      shorting_target = 0,
      symbols = { modified = '[+]', readonly = '[-]' }
    }},
lualine_x = { undo_info, 'encoding', 'fileformat', 'filetype', wordcount },
    lualine_y = { 'progress' },
    lualine_z = { total_lines }
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {{
      'filename',
      path = 2,
      symbols = { modified = '[+]' }
    }},
    lualine_x = { 'location' },
    lualine_y = {},
    lualine_z = {}
  },
})
EOF

set title
set bg=dark " changed by claude for pywal thing
set mouse=a
set nohlsearch
set clipboard+=unnamedplus
set noshowmode
set noruler
set laststatus=2
set noshowcmd
set termguicolors
colorscheme wal
hi Normal guibg=NONE ctermbg=NONE

" Some basics:
nnoremap c "_c
filetype plugin on
syntax on
set encoding=utf-8
set number relativenumber
set wildmode=longest,list,full
autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o
vnoremap . :normal .<CR>

" Goyo plugin makes text more readable when writing prose:
map <leader>f :Goyo \| set bg=light \| set linebreak<CR>
" Spell-check set to <leader>o, 'o' for 'orthography':
map <leader>o :setlocal spell! spelllang=en_us<CR>
" Splits open at the bottom and right, which is non-retarded, unlike vim defaults.
set splitbelow splitright

" Nerd tree
map <leader>n :NERDTreeToggle<CR>
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif
let NERDTreeBookmarksFile = stdpath('data') . '/NERDTreeBookmarks'

" Shortcutting split navigation, saving a keypress:
map <C-h> <C-w>h
map <C-j> <C-w>j
map <C-k> <C-w>k
map <C-l> <C-w>l
" Replace ex mode with gq
map Q gq
" Check file in shellcheck:
map <leader>s :!clear && shellcheck -x %<CR>
" Open my bibliography file in split
map <leader>b :vsp<space>$BIB<CR>
map <leader>r :vsp<space>$REFER<CR>
" Replace all is aliased to S.
nnoremap S :%s//g<Left><Left>
" Compile document, be it groff/LaTeX/markdown/etc.
map <leader>c :w! \| !compiler "%:p"<CR>
" Open corresponding .pdf/.html or preview
map <leader>p :!opout "%:p"<CR><CR>
" Runs a script that cleans out tex build files whenever I close out of a .tex file.
autocmd VimLeave *.tex !latexmk -c %
" Ensure files are read as what I want:
let g:vimwiki_ext2syntax = {'.Rmd': 'markdown', '.rmd': 'markdown','.md': 'markdown', '.markdown': 'markdown', '.mdown': 'markdown'}
map <leader>v :VimwikiIndex<CR>
let g:vimwiki_list = [{'path': '~/.local/share/nvim/vimwiki', 'syntax': 'markdown', 'ext': '.md'}]
autocmd BufRead,BufNewFile /tmp/calcurse*,~/.calcurse/notes/* set filetype=markdown
autocmd BufRead,BufNewFile *.ms,*.me,*.mom,*.man set filetype=groff
autocmd BufRead,BufNewFile *.tex set filetype=tex
" Save file as sudo on files that require root permission
cabbrev w!! execute 'silent! write !sudo tee % >/dev/null' <bar> edit!
" Enable Goyo by default for mutt writing
autocmd BufRead,BufNewFile /tmp/neomutt* :Goyo 80 | call feedkeys("jk")
autocmd BufRead,BufNewFile /tmp/neomutt* map ZZ :Goyo!\|x!<CR>
autocmd BufRead,BufNewFile /tmp/neomutt* map ZQ :Goyo!\|q!<CR>
" Automatically deletes all trailing whitespace and newlines at end of file on save. & reset cursor position
  autocmd BufWritePre * let currPos = getpos(".")
autocmd BufWritePre * %s/\s\+$//e
autocmd BufWritePre * %s/\n\+\%$//e
  autocmd BufWritePre *.[ch] %s/\%$/\r/e " add trailing newline for ANSI C standard
  autocmd BufWritePre *neomutt* %s/^--$/-- /e " dash-dash-space signature delimiter in emails
   autocmd BufWritePre * cal cursor(currPos[1], currPos[2])
" When shortcut files are updated, renew bash and ranger configs with new material:
autocmd BufWritePost bm-files,bm-dirs !shortcuts
" Run xrdb whenever Xdefaults or Xresources are updated.
autocmd BufRead,BufNewFile Xresources,Xdefaults,xresources,xdefaults set filetype=xdefaults
autocmd BufWritePost Xresources,Xdefaults,xresources,xdefaults !xrdb %
" Recompile dwmblocks on config edit.
autocmd BufWritePost ~/.local/src/dwmblocks/config.h !cd ~/.local/src/dwmblocks/; sudo make install && { killall -q dwmblocks;setsid -f dwmblocks }
" Turns off highlighting on the bits of code that are changed, so the line that is changed is highlighted but the actual text that has changed stands out on the line and is readable.
if &diff
    highlight! link DiffText MatchParen
endif
" Function for toggling the bottom statusbar: (still works perfectly with lualine)
let s:hidden_all = 0
function! ToggleHiddenAll()
    if s:hidden_all == 0
        let s:hidden_all = 1
        set noshowmode
        set noruler
        set laststatus=0
        set noshowcmd
    else
        let s:hidden_all = 0
        set showmode
        set ruler
        set laststatus=2
        set showcmd
    endif
endfunction
nnoremap <leader>h :call ToggleHiddenAll()<CR>




" Custom command to compile notes into pdf with xelatex"
function! CompileAndClean(...) abort
  " Arguments: template_name (string, optional), use_bib (0/1, optional)
  let l:template_name = get(a:000, 0, '')
  let l:use_bib = get(a:000, 1, -1) " -1 means prompt
  " Get base name and input file
  let l:base = expand('%:t:r')
  let l:input_file = shellescape(expand('%:p'))
  " Determine output directory
  let l:vimwiki_dir = expand("$HOME") . "/.local/share/nvim/vimwiki"
  let l:file_dir = expand('%:p:h')
  if stridx(l:file_dir, l:vimwiki_dir) == 0
    let l:output_dir = expand("$HOME") . "/Documents/Notes"
  else
    let l:output_dir = l:file_dir
  endif
  " Create output directory if it doesn't exist
  if !isdirectory(l:output_dir)
    call mkdir(l:output_dir, 'p')
    echom "Created output directory: " . l:output_dir
  endif
  " Template directory
  let l:template_dir = expand("$HOME") . "/.local/share/default_latex"
  let l:templates = glob(l:template_dir . '/*.tex', 0, 1)
  if empty(l:templates)
    echom "No .tex templates found in " . l:template_dir
    return
  endif
  " Extract basenames for selection (e.g., 'default', 'template2')
  let l:template_basenames = map(copy(l:templates), 'fnamemodify(v:val, ":t:r")')
  " Prompt for template if not provided
  if empty(l:template_name)
    let l:choices = ['Select template:']
    for i in range(len(l:template_basenames))
      call add(l:choices, printf('%d: %s', i+1, l:template_basenames[i]))
    endfor
    let l:selection = inputlist(l:choices)
    if l:selection < 1 || l:selection > len(l:template_basenames)
      echom "Invalid selection. Aborting."
      return
    endif
    let l:template_name = l:template_basenames[l:selection - 1]
  endif
  let l:template_path = l:template_dir . '/' . l:template_name . '.tex'
  if !filereadable(l:template_path)
    echom "Template not found: " . l:template_path
    return
  endif
  " Check for accompanying Lua filter
  let l:filter_path = l:template_dir . '/' . l:template_name . '.lua'
  let l:filter_cmd = ''
  if filereadable(l:filter_path)
    let l:filter_cmd = ' --lua-filter=' . shellescape(l:filter_path)
  endif
" Detect toc: true and bibliography: true in YAML front matter
  let l:yaml = getline(1, 30)
  let l:has_toc = !empty(filter(copy(l:yaml), 'v:val =~ "^\\s*toc:\\s*true"'))
  if l:use_bib == -1
    let l:use_bib = !empty(filter(copy(l:yaml), 'v:val =~ "^\\s*bibliography:\\s*true"')) ? 1 : 0
  endif
  " .tex file path
  let l:tex_file = l:output_dir . '/' . l:base . '.tex'
  " Build pandoc command
  let l:pandoc_cmd = "pandoc -s " . l:input_file . " -o " . shellescape(l:tex_file) . " --template=" . shellescape(l:template_path) . l:filter_cmd
  if l:use_bib
    let l:pandoc_cmd .= " --bibliography=$HOME/.local/share/biblatex/uni.bib --biblatex"
  endif
  echom "Running pandoc: " . l:pandoc_cmd
  let l:pandoc_result = system(l:pandoc_cmd)
  if v:shell_error
    echom "Pandoc failed with error: " . l:pandoc_result
    return
  endif
  " Change to output dir for compilation
  let l:old_dir = getcwd()
  execute 'lcd ' . fnameescape(l:output_dir)
  " XeLaTeX runs
  let l:xelatex_cmd = "xelatex -interaction=nonstopmode " . shellescape(l:base . '.tex')
  echom "Running first xelatex: " . l:xelatex_cmd
  let l:xelatex_result = system(l:xelatex_cmd)
  if v:shell_error
    echom "First xelatex failed: " . l:xelatex_result
    execute 'lcd ' . fnameescape(l:old_dir)
    return
  endif
  " Second pass for TOC without bibliography
  if !l:use_bib && l:has_toc
    echom "Running second xelatex (TOC): " . l:xelatex_cmd
    let l:xelatex_result = system(l:xelatex_cmd)
    if v:shell_error
      echom "Second xelatex failed: " . l:xelatex_result
      execute 'lcd ' . fnameescape(l:old_dir)
      return
    endif
  endif
  if l:use_bib
    " Biber
    let l:biber_cmd = "biber " . shellescape(l:base)
    echom "Running biber: " . l:biber_cmd
    let l:biber_result = system(l:biber_cmd)
    if v:shell_error
      echom "Biber failed: " . l:biber_result
      execute 'lcd ' . fnameescape(l:old_dir)
      return
    endif
    " Second XeLaTeX
    echom "Running second xelatex: " . l:xelatex_cmd
    let l:xelatex_result = system(l:xelatex_cmd)
    if v:shell_error
      echom "Second xelatex failed: " . l:xelatex_result
      execute 'lcd ' . fnameescape(l:old_dir)
      return
    endif
    " Third XeLaTeX (for final refs/toc)
    echom "Running third xelatex: " . l:xelatex_cmd
    let l:xelatex_result = system(l:xelatex_cmd)
    if v:shell_error
      echom "Third xelatex failed: " . l:xelatex_result
      execute 'lcd ' . fnameescape(l:old_dir)
      return
    endif
  endif
  " Restore directory
  execute 'lcd ' . fnameescape(l:old_dir)
  echom "Compilation complete. Check PDF at " . l:output_dir . '/' . l:base . '.pdf'
  " Run cleaner script with arguments
  let l:shell_script = "$HOME/.local/bin/cleaner " . shellescape(l:output_dir) . " " . shellescape(l:base)
  echom "Running shell script: " . l:shell_script
  let l:script_result = system(l:shell_script)
  if v:shell_error
    echom "Shell script failed: " . l:script_result
  endif
endfunction
" Mappings
nnoremap <leader>1 :call CompileAndClean('default')<CR>
nnoremap <leader>2 :call CompileAndClean('template2')<CR>
nnoremap <leader>3 :call CompileAndClean()<CR>



" === DIARY COMPILATION — now completely silent & clean ===
function! CompileDiary() abort
  let l:output_dir = expand("$HOME") . "/Documents/Anotacoes/VimwikiContinuous"
  if !isdirectory(l:output_dir)
    call mkdir(l:output_dir, 'p')
    echom "Created Diary output directory: " . l:output_dir
  endif
  let l:base = "diario"
  let l:tex_file = l:output_dir . '/' . l:base . '.tex'
  let l:pdf_file = l:output_dir . '/' . l:base . '.pdf'
  let l:diary_dir = expand("~/.local/share/nvim/vimwiki/diary")
  let l:md_files = glob(l:diary_dir . '/*.md', 0, 1)
  call sort(l:md_files)
  let l:date_files = []
  for l:f in l:md_files
    let l:name = fnamemodify(l:f, ':t:r')
    if l:name =~ '^\d\{4\}-\d\{2\}-\d\{2\}$'
      call add(l:date_files, l:f)
    endif
  endfor
  if empty(l:date_files)
    echom "No diary entries yet."
    return
  endif
  let l:month_translation = {
    \ '01': 'Janeiro', '02': 'Fevereiro', '03': 'Março', '04': 'Abril',
    \ '05': 'Maio', '06': 'Junho', '07': 'Julho', '08': 'Agosto',
    \ '09': 'Setembro', '10': 'Outubro', '11': 'Novembro', '12': 'Dezembro'
    \ }
  let l:first_date = fnamemodify(l:date_files[0], ':t:r')
  let l:last_date = fnamemodify(l:date_files[-1], ':t:r')
  let l:first_parts = split(l:first_date, '-')
  let l:last_parts = split(l:last_date, '-')
  let l:first_mon = l:month_translation[l:first_parts[1]]
  let l:last_mon = l:month_translation[l:last_parts[1]]
  let l:first_year = l:first_parts[0]
  let l:last_year = l:last_parts[0]
  if l:first_year == l:last_year
    let l:title = "Diário " . l:first_mon . " - " . l:last_mon . " " . l:first_year
  else
    let l:title = "Diário " . l:first_mon . " " . l:first_year . " - " . l:last_mon . " " . l:last_year
  endif
  let l:temp_md = '/tmp/diary_concat.md'
  if filereadable(l:temp_md) | call delete(l:temp_md) | endif
  for l:file in l:date_files
    let l:date_key = fnamemodify(l:file, ':t:r')
    let l:parts = split(l:date_key, '-')
    let l:day = printf('%d', str2nr(l:parts[2]))
    let l:mon_name = l:month_translation[l:parts[1]]
    let l:year = l:parts[0]
    let l:formatted_title = l:day . ' de ' . l:mon_name . ' de ' . l:year
    call writefile(['# ' . l:formatted_title, ''], l:temp_md, 'a')
    call writefile(readfile(l:file), l:temp_md, 'a')
    call writefile([''], l:temp_md, 'a')
  endfor
  let l:template_path = expand("$HOME") . "/.local/share/default_latex/diary.tex"
  let l:pandoc_cmd = "pandoc -s " . shellescape(l:temp_md) .
        \ " -o " . shellescape(l:tex_file) .
        \ " --template=" . shellescape(l:template_path) .
        \ " --metadata title=" . shellescape(l:title)
  let l:pandoc_result = system(l:pandoc_cmd)
  if v:shell_error
    echom "Pandoc failed: " . l:pandoc_result
    call delete(l:temp_md)
    return
  endif
  " === Compile TWICE (silences rerun/label warnings) ===
  let l:old_dir = getcwd()
  execute 'lcd ' . fnameescape(l:output_dir)
  let l:xelatex_cmd = "xelatex -interaction=nonstopmode " . shellescape(l:base . '.tex')
  echom "Compiling diary PDF..."
  call system(l:xelatex_cmd) " first run
  call system(l:xelatex_cmd) " second run (final TOC/hyperref)
  execute 'lcd ' . fnameescape(l:old_dir)
  " Cleanup
  call delete(l:temp_md)
  silent! call system("$HOME/.local/bin/cleaner " . shellescape(l:output_dir) . " " . shellescape(l:base))
  echom "Diary PDF ready → " . l:pdf_file
endfunction
nnoremap <leader>4 :call CompileDiary()<CR>





" TESTE DA FUNÇÃO DE TABELA:
" ── Cell sanitizer: fixes ^ and unicode superscripts for LaTeX ──────────────
function! s:SanitizeCell(cell)
  let l:c = a:cell
  " Map unicode superscript digits to ASCII
  let l:umap = {
    \ '⁰':'0','¹':'1','²':'2','³':'3','⁴':'4',
    \ '⁵':'5','⁶':'6','⁷':'7','⁸':'8','⁹':'9'
    \ }
  for [l:uni, l:num] in items(l:umap)
    let l:c = substitute(l:c, l:uni, l:num, 'g')
  endfor
  " Convert explicit ^{...} → \textsuperscript{...}
  let l:c = substitute(l:c, '\^{\([^}]*\)}', '\\textsuperscript{\1}', 'g')
  " Convert bare ^X or ^12 → \textsuperscript{X}
  let l:c = substitute(l:c, '\^\([0-9a-zA-Z+\-][0-9]*\)', '\\textsuperscript{\1}', 'g')
  return l:c
endfunction

" ── Quote-aware splitter ─────────────────────────────────────────────────────
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

" ── Pipe row splitter: splits a markdown | row | into cells ─────────────────
function! s:SplitPipeRow(line)
  " Strip leading and trailing pipes, then split on |
  let l:stripped = substitute(a:line, '^\s*|\(.*\)|\s*$', '\1', '')
  let l:cells = split(l:stripped, '|')
  return map(l:cells, 'trim(v:val)')
endfunction

" ── Detect if selected lines form a markdown pipe table ──────────────────────
function! s:IsPipeTable(lines)
  if empty(a:lines)
    return 0
  endif
  " First line must start with |
  if a:lines[0] !~ '^\s*|'
    return 0
  endif
  " Must have at least a header + separator row
  if len(a:lines) < 2
    return 0
  endif
  " Second line must be a separator row like |---|---|
  if a:lines[1] !~ '^\s*|[-| :]*|'
    return 0
  endif
  return 1
endfunction

" ── Parse a markdown pipe table into headers + data rows ─────────────────────
function! s:ParsePipeTable(lines)
  " First line = headers, second line = separator (skip), rest = data
  let l:headers = s:SplitPipeRow(a:lines[0])
  let l:data_rows_raw = a:lines[2:]  " skip separator at index 1
  let l:data_rows = []
  for l:row in l:data_rows_raw
    " Skip empty lines or lines that don't look like table rows
    if l:row =~ '^\s*|'
      call add(l:data_rows, l:row)
    endif
  endfor
  return [l:headers, l:data_rows]
endfunction

" ── LaTeX output builder ─────────────────────────────────────────────────────
function! s:BuildLatex(headers, data_rows, num_cols, caption, label, is_pipe)
  let latex = [
    \ '\begin{table}[H]',
    \ '\centering',
    \ '\caption{' . a:caption . '}',
    \ '\label{' . a:label . '}',
    \ '\begin{tabular}{l' . repeat('c', a:num_cols - 1) . '}'
    \ ]
  let header_cells = map(copy(a:headers), '"\\textbf{" . escape(s:SanitizeCell(trim(v:val)), "&%#") . "}"')
  call add(latex, '\toprule')
  call add(latex, join(header_cells, ' & ') . ' \\')
  call add(latex, '\midrule')
  for row in a:data_rows
    if a:is_pipe
      let cells = s:SplitPipeRow(row)
    else
      let cells = s:SplitRespectingQuotes(row, ',')
    endif
    let row_cells = map(range(a:num_cols), 'v:val < len(cells) ? escape(s:SanitizeCell(trim(cells[v:val])), "&%#") : ""')
    call add(latex, join(row_cells, ' & ') . ' \\')
  endfor
  call add(latex, '\bottomrule')
  call add(latex, '\end{tabular}')
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

  " ── AUTO-DETECT PIPE TABLE ────────────────────────────────────────────────
  if s:IsPipeTable(lines)
    let [l:headers, l:data_rows] = s:ParsePipeTable(lines)
    let l:num_cols = len(l:headers)
    if l:num_cols == 0
      echom "Error: No columns detected in pipe table"
      return
    endif
    " Still ask output mode — pipe table → LaTeX is the main use case,
    " but markdown mode just re-emits it cleanly (useful for reformatting)
    let mode_choice = input("Pipe table detected. Output (l)aTeX or (m)arkdown [default l]: ")
    if empty(mode_choice)
      let mode_choice = 'l'
    endif
    if mode_choice =~? 'm'
      " Re-emit as clean markdown (normalizes spacing)
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
    " LaTeX output
    let caption = input('Enter caption: ', 'Table Caption')
    let label = input('Enter label (e.g., tab:yourlabel): ', 'tab:yourlabel')
    let latex = s:BuildLatex(l:headers, l:data_rows, l:num_cols, caption, label, 1)
    execute a:firstline . ',' . a:lastline . 'delete _'
    call append(a:firstline - 1, latex)
    return
  endif

  " ── CSV / MANUAL INPUT PATH ───────────────────────────────────────────────
  let mode_choice = input("Output mode (l)aTeX or (m)arkdown [default l]: ")
  if empty(mode_choice)
    let mode_choice = 'l'
  endif
  if mode_choice !~ '^[lmLM]$'
    echom "Invalid mode. Use l or m."
    return
  endif
  let use_markdown = (mode_choice =~? 'm')
  let delimiter = input("Enter the delimiter (default is ','): ")
  if empty(delimiter)
    let delimiter = ','
  endif
  let num_header_lines = input("Enter the number of header lines (0, 1, or 2): ")
  if num_header_lines !~ '^[0-2]$'
    echom "Invalid input. Please enter 0, 1, or 2."
    return
  endif
  let num_header_lines = str2nr(num_header_lines)
  if num_header_lines == 0
    let header_input = input("Enter headers separated by commas: ")
    let headers = s:SplitRespectingQuotes(header_input, delimiter)
    let data_rows = lines
  elseif num_header_lines == 1
    if len(lines) < 1
      echom "Error: Not enough lines selected"
      return
    endif
    let headers = s:SplitRespectingQuotes(lines[0], delimiter)
    let data_rows = lines[1:]
  elseif num_header_lines == 2
    if len(lines) < 2
      echom "Error: Not enough lines selected for composite headers"
      return
    endif
    let group_headers = s:SplitRespectingQuotes(lines[0], delimiter)
    let subheaders = s:SplitRespectingQuotes(lines[1], delimiter)
    let data_rows = lines[2:]
    let group_names = filter(copy(group_headers[1:]), '!empty(v:val)')
    let num_groups = len(group_names)
    if num_groups == 0
      echom "Error: No group headers found in first row (columns 2+)"
      return
    endif
    let num_subheaders = len(subheaders) - 1
    if num_subheaders <= 0
      echom "Error: Not enough subheaders found"
      return
    endif
    if num_subheaders % num_groups != 0
      echom "Error: Subheaders (" . num_subheaders . ") not evenly divisible by groups (" . num_groups . ")"
      return
    endif
    let span = num_subheaders / num_groups
  endif
  if num_header_lines == 2
    let num_cols = len(subheaders)
  else
    let num_cols = len(headers)
  endif
  if num_cols == 0
    echom "Error: No columns detected"
    return
  endif
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
      let cells = s:SplitRespectingQuotes(row, delimiter)
      let row_cells = map(range(num_cols), 'v:val < len(cells) ? cells[v:val] : ""')
      call add(md, '| ' . join(row_cells, ' | ') . ' |')
    endfor
    execute a:firstline . ',' . a:lastline . 'delete _'
    call append(a:firstline - 1, md)
    return
  endif
  " ── LATEX OUTPUT (csv, composite header path) ─────────────────────────────
  let caption = input('Enter caption: ', 'Table Caption')
  let label = input('Enter label (e.g., tab:yourlabel): ', 'tab:yourlabel')
  if num_header_lines == 2
    let latex = [
      \ '\begin{table}[H]',
      \ '\centering',
      \ '\caption{' . caption . '}',
      \ '\label{' . label . '}',
      \ '\begin{tabular}{l' . repeat('c', num_cols - 1) . '}'
      \ ]
    let group_row = ['']
    for i in range(num_groups)
      call add(group_row, '\multicolumn{' . span . '}{c}{\textbf{' . escape(s:SanitizeCell(group_names[i]), "&%#") . '}}')
    endfor
    call add(latex, '\toprule')
    call add(latex, join(group_row, ' & ') . ' \\')
    let cmidrules = []
    for i in range(num_groups)
      let start_col = 2 + i * span
      let end_col = start_col + span - 1
      call add(cmidrules, '\cmidrule(lr){' . start_col . '-' . end_col . '}')
    endfor
    call add(latex, join(cmidrules, ' '))
    let subheader_cells = map(subheaders, '"\\textbf{" . escape(s:SanitizeCell(trim(v:val)), "&%#") . "}"')
    call add(latex, join(subheader_cells, ' & ') . ' \\')
    call add(latex, '\midrule')
    for row in data_rows
      let cells = s:SplitRespectingQuotes(row, delimiter)
      let row_cells = map(range(num_cols), 'v:val < len(cells) ? escape(s:SanitizeCell(trim(cells[v:val])), "&%#") : ""')
      call add(latex, join(row_cells, ' & ') . ' \\')
    endfor
    call add(latex, '\bottomrule')
    call add(latex, '\end{tabular}')
    call add(latex, '\end{table}')
  else
    let latex = s:BuildLatex(headers, data_rows, num_cols, caption, label, 0)
  endif
  execute a:firstline . ',' . a:lastline . 'delete _'
  call append(a:firstline - 1, latex)
endfunction

command! -range Table <line1>,<line2>call Table()
vnoremap <leader>t :Table<CR>

" FINAL DA FUNCAO DE TABELA

" criador de tabela em md
function! InsertMarkdownTable()
  let l:input = input("Column headers (comma-separated): ")
  if empty(l:input)
    return
  endif
  let l:headers = map(split(l:input, ','), 'trim(v:val)')
  let l:num_cols = len(l:headers)
  let l:header_row = '| ' . join(l:headers, ' | ') . ' |'
  let l:sep_row = '|' . repeat('---|', l:num_cols)
  let l:data_row = '|' . repeat(' |', l:num_cols)
  " Insert below current line and position cursor on first data cell
  call append(line('.'), [l:header_row, l:sep_row, l:data_row])
  " Move to first data cell
  call cursor(line('.') + 3, 3)
  startinsert
endfunction

nnoremap <leader>tm :call InsertMarkdownTable()<CR>

" Sets automatically VimWiki Diary entry updates in the Diary index
let g:vimwiki_diary_auto_index = 1
autocmd BufLeave ~/.local/share/nvim/vimwiki/diary/*.md :VimwikiDiaryGenerateLinks


" Open People Index
nnoremap <leader>wp :edit ~/.local/share/nvim/people/index.md<CR>


" Load command shortcuts generated from bm-dirs and bm-files via shortcuts script.
" Here leader is ";".
" So ":vs ;cfz" will expand into ":vs /home/<user>/.config/zsh/.zshrc"
" if typed fast without the timeout.
silent! source ~/.config/nvim/shortcuts.vim


" create the yaml config for each vimwiki markdown file
autocmd BufNewFile ~/.local/share/nvim/vimwiki/*.md call InsertMarkdownHeader()

function! InsertMarkdownHeader()
  if expand('%:p') =~ '/vimwiki/diary/'
    return
  endif
  let l:filename = expand('%:t:r')
  let l:date = strftime('%Y-%m-%d')
  call setline(1, [
    \ '---',
    \ 'title: ' . l:filename,
    \ 'subject: ',
    \ 'date: ' . l:date,
    \ 'toc: true',
    \ 'bibliography: false',
    \ '---',
    \ '',
    \ ''
    \ ])
  call cursor(2, len('title: ' . l:filename) + 1)
endfunction

" source the image function from its file image.vim

source ~/.config/nvim/functions/image.vim

" === HTML heading shortcuts with blank line + <++> and correct cursor ===
augroup html_headings
  autocmd!
  autocmd FileType html nnoremap <buffer> <leader>1 i<h1></h1><CR><CR><++><Esc>kk0f>a
  autocmd FileType html nnoremap <buffer> <leader>2 i<h2></h2><CR><CR><++><Esc>kk0f>a
  autocmd FileType html nnoremap <buffer> <leader>3 i<h3></h3><CR><CR><++><Esc>kk0f>a
  autocmd FileType html nnoremap <buffer> <leader>4 i<h4></h4><CR><CR><++><Esc>kk0f>a
  autocmd FileType html nnoremap <buffer> <leader>5 i<h5></h5><CR><CR><++><Esc>kk0f>a
  autocmd FileType html nnoremap <buffer> <leader>6 i<h6></h6><CR><CR><++><Esc>kk0f>a
  autocmd FileType html nnoremap <buffer> <leader>p i<p></p><Esc>F<i
  autocmd FileType html nnoremap <buffer> <leader>d i<div class=""><CR><CR></div><Esc>kkf"a
augroup END
augroup markdown_formatting
  autocmd!
  autocmd FileType markdown nnoremap <buffer> <leader>B viW<esc>`>a**<esc>`<i**<esc>lella
  autocmd FileType markdown nnoremap <buffer> <leader>i viW<esc>a*<esc>bi*<esc>lel<esc>a
augroup END
" Trying to make UNDO permanent across sessions
set undofile
set undodir^=$HOME/.local/state/nvim/undo//
