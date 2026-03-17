function! InsertImage()
  let l:downloads = expand("$HOME") . "/Downloads"
  if !isdirectory(l:downloads)
    echom "~/Downloads not found"
    return
  endif

  let l:tmpfile = tempname()

  " Open a terminal buffer running fzf, write selection to tmpfile
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
  " Close the terminal buffer
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

  let l:width = input("Width (e.g. 60%, \\linewidth) [default 80%]: ")
  if empty(l:width) | let l:width = '80%' | endif

  let l:caption = input("Caption (leave empty for none): ")

  if !empty(l:caption)
    let l:line = '![' . l:caption . '](' . l:selected . '){width=' . l:width . '}'
  else
    let l:line = '![](' . l:selected . '){width=' . l:width . '}'
  endif

  call append(line('.'), l:line)
  echom "Inserted: " . l:line
endfunction

nnoremap <leader>ii :call InsertImage()<CR>
