" ── InsertCitation: fuzzy-select a BibTeX entry and insert [@citekey] ────────
" Mirrors the structure of InsertImage / image.vim

function! InsertCitation()
  let l:bibfile = expand("$HOME") . "/.local/share/biblatex/uni.bib"
  if !filereadable(l:bibfile)
    echom "BibTeX file not found: " . l:bibfile
    return
  endif

  let l:tmpfile  = tempname()
  let l:listfile = tempname()

  " Python parses the bib file and writes tab-separated display lines:
  " citekey <TAB> Author (Year) <TAB> Title
  let l:pylines = [
    \ 'import re, sys',
    \ 'bibfile  = sys.argv[1]',
    \ 'listfile = sys.argv[2]',
    \ 'text     = open(bibfile, encoding="utf-8", errors="ignore").read()',
    \ 'entries  = re.split(r"(?=@\w+\s*\{)", text)',
    \ 'results  = []',
    \ 'for entry in entries:',
    \ '    km = re.match(r"@\w+\s*\{\s*([^,]+),", entry)',
    \ '    if not km: continue',
    \ '    key    = km.group(1).strip()',
    \ '    am     = re.search(r"author\s*=\s*[{\"](.*?)[}\"]", entry, re.I | re.S)',
    \ '    ym     = re.search(r"year\s*=\s*[{\"]*(\d{4})", entry, re.I)',
    \ '    tm     = re.search(r"title\s*=\s*[{\"](.*?)[}\"]", entry, re.I | re.S)',
    \ '    author = am.group(1).split(" and ")[0].split(",")[0].strip() if am else "?"',
    \ '    year   = ym.group(1) if ym else "?"',
    \ '    title  = re.sub(r"[{}]", "", tm.group(1)).strip()[:60] if tm else "?"',
    \ '    results.append(key + "\t" + author + " (" + year + ")" + "\t" + title)',
    \ 'open(listfile, "w").write("\n".join(results))',
    \ ]

  let l:pyfile = tempname() . '.py'
  call writefile(l:pylines, l:pyfile)
  call system('python3 ' . shellescape(l:pyfile) .
    \ ' ' . shellescape(l:bibfile) .
    \ ' ' . shellescape(l:listfile))
  call delete(l:pyfile)

  if !filereadable(l:listfile) || empty(readfile(l:listfile))
    echom "No entries found in bib file"
    return
  endif

  botright 15new
  call termopen(
    \ 'cat ' . shellescape(l:listfile) .
    \ ' | column -t -s "	"' .
    \ ' | fzf --prompt="Select reference: "' .
    \ ' > ' . shellescape(l:tmpfile),
    \ {'on_exit': function('s:CitationSelected', [l:tmpfile, l:listfile])})
  startinsert
endfunction

function! s:CitationSelected(tmpfile, listfile, job_id, code, event)
  bdelete!
  call delete(a:listfile)
  if a:code != 0 || !filereadable(a:tmpfile)
    echom "No reference selected"
    return
  endif
  let l:lines = readfile(a:tmpfile)
  call delete(a:tmpfile)
  if empty(l:lines) || empty(trim(l:lines[0]))
    echom "No reference selected"
    return
  endif
  " First whitespace-delimited token is the citekey
  let l:citekey = trim(split(trim(l:lines[0]))[0])
  call timer_start(50, function('s:InsertCitekey', [l:citekey]))
endfunction

function! s:InsertCitekey(citekey, timer)
  let l:citation = '[@' . a:citekey . ']'
  execute "normal! a" . l:citation
  echom "Inserted: " . l:citation
endfunction

nnoremap <leader>ic :call InsertCitation()<CR>
