source ~/.cache/wal/colors-wal.vim

set background=dark
hi clear
if exists("syntax_on") | syntax reset | endif
let g:colors_name = "wal"

exe 'hi Normal       guifg='.foreground.' guibg=NONE'
exe 'hi Comment      guifg='.color8
exe 'hi Constant     guifg='.color6
exe 'hi String       guifg='.color2
exe 'hi Identifier   guifg='.color4
exe 'hi Statement    guifg='.color1
exe 'hi PreProc      guifg='.color5
exe 'hi Type         guifg='.color3
exe 'hi Special      guifg='.color6
exe 'hi Error        guifg='.color1.' guibg=NONE'
exe 'hi Todo         guifg='.color4.' guibg=NONE'
exe 'hi LineNr       guifg='.color8
exe 'hi CursorLineNr guifg='.foreground
exe 'hi Visual       guibg='.color8
exe 'hi StatusLine   guifg='.foreground.' guibg='.color0
exe 'hi VertSplit    guifg='.color8
