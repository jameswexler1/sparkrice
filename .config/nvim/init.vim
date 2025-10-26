let mapleader =","

if ! filereadable(system('echo -n "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/autoload/plug.vim"'))
	echo "Downloading junegunn/vim-plug to manage plugins..."
	silent !mkdir -p ${XDG_CONFIG_HOME:-$HOME/.config}/nvim/autoload/
	silent !curl "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" > ${XDG_CONFIG_HOME:-$HOME/.config}/nvim/autoload/plug.vim
	autocmd VimEnter * PlugInstall
endif

map ,, :keepp /<++><CR>ca<
imap ,, <esc>:keepp /<++><CR>ca<

call plug#begin(system('echo -n "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/plugged"'))
Plug 'tpope/vim-surround'
Plug 'preservim/nerdtree'
Plug 'junegunn/goyo.vim'
Plug 'jreybert/vimagit'
Plug 'vimwiki/vimwiki'
Plug 'vim-airline/vim-airline'
Plug 'tpope/vim-commentary'
Plug 'ap/vim-css-color'
call plug#end()

set title
set bg=light
"set go=a
set mouse=a
set nohlsearch
set clipboard+=unnamedplus
set noshowmode
set noruler
set laststatus=0
set noshowcmd
colorscheme vim

" Some basics:
	nnoremap c "_c
	filetype plugin on
	syntax on
	set encoding=utf-8
	set number relativenumber
" Enable autocompletion:
	set wildmode=longest,list,full
" Disables automatic commenting on newline:
	autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o
" Perform dot commands over visual blocks:
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

" vim-airline
	if !exists('g:airline_symbols')
		let g:airline_symbols = {}
	endif
	let g:airline_symbols.colnr = ' C:'
	let g:airline_symbols.linenr = ' L:'
	let g:airline_symbols.maxlinenr = '☰ '

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
	map <leader>p :!opout "%:p"<CR>

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

" Function for toggling the bottom statusbar:
let s:hidden_all = 0
function! ToggleHiddenAll()
    if s:hidden_all  == 0
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
  let l:use_bib = get(a:000, 1, -1)  " -1 means prompt

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

  " Prompt for bibliography if not specified
  if l:use_bib == -1
    let l:bib_choice = confirm("Include bibliography?", "&Yes\n&No", 2)
    let l:use_bib = (l:bib_choice == 1 ? 1 : 0)
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

  " XeLaTeX runs (extra for bib)
  let l:xelatex_cmd = "xelatex -interaction=nonstopmode " . shellescape(l:base . '.tex')
  echom "Running first xelatex: " . l:xelatex_cmd
  let l:xelatex_result = system(l:xelatex_cmd)
  if v:shell_error
    echom "First xelatex failed: " . l:xelatex_result
    execute 'lcd ' . fnameescape(l:old_dir)
    return
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
nnoremap <leader>p :call CompileAndClean('default', 0)<CR>  " Default template, no bib
nnoremap <leader>2 :call CompileAndClean('template2', 0)<CR>  " Template2, no bib
nnoremap <leader>3 :call CompileAndClean()<CR>



" TESTE DA FUNÇÃO DE TABELA:

function! Table() range
    " Get selected lines
    let lines = getline(a:firstline, a:lastline)
    if empty(lines)
        echom "No lines selected"
        return
    endif

    " Prompt for delimiter
    let delimiter = input("Enter the delimiter (default is ','): ")
    if empty(delimiter)
        let delimiter = ','
    endif

    " Prompt for number of header lines
    let num_header_lines = input("Enter the number of header lines (0, 1, or 2): ")
    if num_header_lines !~ '^[0-2]$'
        echom "Invalid input. Please enter 0, 1, or 2."
        return
    endif
    let num_header_lines = str2nr(num_header_lines)

    " Process headers and data rows based on input
    if num_header_lines == 0
        let header_input = input("Enter headers separated by commas: ")
        let headers = split(header_input, ',')
        let headers = map(headers, 'trim(v:val)')
        let data_rows = lines
    elseif num_header_lines == 1
        if len(lines) < 1
            echom "Error: Not enough lines selected"
            return
        endif
        let headers = split(lines[0], delimiter)
        let data_rows = lines[1:]
    elseif num_header_lines == 2
        if len(lines) < 2
            echom "Error: Not enough lines selected for composite headers"
            return
        endif
        let group_headers = split(lines[0], delimiter)
        let subheaders = split(lines[1], delimiter)
        let data_rows = lines[2:]
        let group_names = filter(copy(group_headers[1:]), '!empty(v:val)')
        let num_groups = len(group_names)
        if num_groups == 0
            echom "Error: No group headers found"
            return
        endif
        let num_subheaders = len(subheaders) - 1
        if num_subheaders % num_groups != 0
            echom "Error: Subheaders not evenly divisible by number of groups"
            return
        endif
        let span = num_subheaders / num_groups
    endif

    " Set number of columns
    if num_header_lines == 2
        let num_cols = len(subheaders)
    else
        let num_cols = len(headers)
    endif

    " Prompt for caption and label
    let caption = input('Enter caption: ', 'Table Caption')
    let label = input('Enter label (e.g., tab:yourlabel): ', 'tab:yourlabel')

    " Build LaTeX table
    let latex = ['\begin{table}[H]', '\centering', '\caption{' . caption . '}', '\label{' . label . '}', '\begin{tabular}{l' . repeat('c', num_cols - 1) . '}']

    if num_header_lines == 2
        " Composite header with groups
        let group_row = ['']
        for i in range(num_groups)
            call add(group_row, '\multicolumn{' . span . '}{c}{\textbf{' . escape(group_names[i], "&%#") . '}}')
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
        let subheader_cells = map(subheaders, '"\\textbf{" . escape(trim(v:val), "&%#") . "}"')
        call add(latex, join(subheader_cells, ' & ') . ' \\')
        call add(latex, '\midrule')
    else
        " Simple header
        let header_cells = map(headers, '"\\textbf{" . escape(trim(v:val), "&%#") . "}"')
        call add(latex, '\toprule')
        call add(latex, join(header_cells, ' & ') . ' \\')
        call add(latex, '\midrule')
    endif

    " Add data rows
    for row in data_rows
        let cells = split(row, delimiter)
        let row_cells = map(range(num_cols), 'v:val < len(cells) ? escape(trim(cells[v:val]), "&%#") : ""')
        call add(latex, join(row_cells, ' & ') . ' \\')
    endfor

    " Close table
    call add(latex, '\bottomrule')
    call add(latex, '\end{tabular}')
    call add(latex, '\end{table}')

    " Replace selection with table
    execute a:firstline . ',' . a:lastline . 'delete _'
    call append(a:firstline - 1, latex)
endfunction

command! -range Table <line1>,<line2>call Table()



highlight SpellBad ctermfg=red ctermbg=none guifg=red guibg=none gui=underline

" Sets automatically VimWiki Diary entry updates in the Diary index

let g:vimwiki_diary_auto_index = 1

" Open People Index

nnoremap <leader>wp :edit ~/.local/share/nvim/people/index.md<CR>

" Load command shortcuts generated from bm-dirs and bm-files via shortcuts script.
" Here leader is ";".
" So ":vs ;cfz" will expand into ":vs /home/<user>/.config/zsh/.zshrc"
" if typed fast without the timeout.
silent! source ~/.config/nvim/shortcuts.vim



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
