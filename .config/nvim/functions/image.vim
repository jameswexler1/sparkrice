function! InsertImage()
  let l:downloads = expand("$HOME") . "/Downloads"
  if !isdirectory(l:downloads)
    echom "~/Downloads not found"
    return
  endif
  let l:tmpfile = tempname()
  botright 15new
  call termopen(
    \ "find " . shellescape(l:downloads) .
    \ " -maxdepth 2 -type f" .
    \ " \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg'" .
    \ " -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.webp' \\)" .
    \ " | fzf --prompt='Select image: ' > " . l:tmpfile,
    \ {'on_exit': function('s:ImageSelected', [l:tmpfile])})
  startinsert
endfunction

function! s:ImageSelected(tmpfile, job_id, code, event)
  bdelete!
  if a:code != 0 || !filereadable(a:tmpfile)
    echom "No image selected"
    return
  endif
  let l:selected = trim(readfile(a:tmpfile)[0])
  call delete(a:tmpfile)
  if empty(l:selected)
    echom "No image selected"
    return
  endif
  call timer_start(50, function('s:ImagePrompt', [l:selected]))
endfunction

function! s:ImagePrompt(selected, timer)
  let l:mode = input("Insert as (m)arkdown or (l)aTeX centered figure [default l]: ")
  if empty(l:mode) | let l:mode = 'l' | endif
  if l:mode =~? 'm'
    let l:width = input("Width (e.g. 60%, 80%) [default 80%]: ")
    if empty(l:width) | let l:width = '80%' | endif
    let l:caption = input("Caption (leave empty for none): ")
    if !empty(l:caption)
      let l:line = '![' . l:caption . '](' . a:selected . '){width=' . l:width . '}'
    else
      let l:line = '![](' . a:selected . '){width=' . l:width . '}'
    endif
    call append(line('.'), l:line)
    echom "Inserted: " . l:line
  else
    let l:width = input("Width (e.g. 0.8\\linewidth, 0.5\\linewidth) [default 0.8\\linewidth]: ")
    if empty(l:width) | let l:width = '0.8\linewidth' | endif
    let l:caption = input("Caption (leave empty for none): ")
    let l:lines = [
      \ '```{=latex}',
      \ '\begin{figure}[H]',
      \ '\centering',
      \ '\includegraphics[width=' . l:width . ']{' . a:selected . '}',
      \ ]
    if !empty(l:caption)
      call add(l:lines, '\caption{' . l:caption . '}')
    endif
    call add(l:lines, '\end{figure}')
    call add(l:lines, '```')
    call append(line('.'), l:lines)
    echom "Inserted image: " . a:selected
  endif
endfunction

nnoremap <leader>ii :call InsertImage()<CR>
