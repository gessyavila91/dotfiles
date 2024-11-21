" Habilitar el uso de las flechas en todos los modos
set nocompatible  " Para evitar que Neovim se comporte como Vi
map <Up> k
map <Down> j
map <Left> h
map <Right> l

set mouse=a  " Habilita el ratón en todos los modos

:set number
" :set relativenumber
:set autoindent
:set tabstop=4
:set shiftwidth=4
:set smarttab
:set softtabstop=4
:set mouse=a

call plug#begin('~/.vim/plugged')

" Otros plugins
Plug 'http://github.com/tpope/vim-surround'
" Plug 'https://github.com/preservim/nerdtree'
Plug 'https://github.com/nvim-tree/nvim-tree.lua'
Plug 'https://github.com/tpope/vim-commentary'
Plug 'https://github.com/vim-airline/vim-airline'
Plug 'https://github.com/neoclide/coc.nvim'
Plug 'https://github.com/ryanoasis/vim-devicons'
Plug 'https://github.com/preservim/tagbar'
Plug 'https://github.com/terryma/vim-multiple-cursors'
Plug 'https://github.com/ap/vim-css-color'
Plug 'neoclide/vim-jetbrains-keymap'


" Agregar el tema Dracula
Plug 'dracula/vim', { 'as': 'dracula' }

call plug#end()

" nnoremap <C-f> :NERDTreeFocus<CR>
" nnoremap <C-n> :NERDTree<CR>
" nnoremap <C-t> :NERDTreeToggle<CR>
" nnoremap <C-l> :call CocActionAsync('jumpDefinition')<CR>

nmap <F8> :TagbarToggle<CR>

:set completeopt-=preview " For No Previews

let g:NERDTreeDirArrowExpandable="+"
let g:NERDTreeDirArrowCollapsible="~"

" --- Just Some Notes ---
" :PlugClean :PlugInstall :UpdateRemotePlugins
"
" :CocInstall coc-python
" :CocInstall coc-clangd
" :CocInstall coc-snippets
" :CocCommand snippets.edit... FOR EACH FILE TYPE

" air-line
let g:airline_powerline_fonts = 1

if !exists('g:airline_symbols')
    let g:airline_symbols = {}
endif

" ################ airline ################
" Configuración de airline (ya la tienes en tu archivo, pero agregaré una opción visual más moderna)
let g:airline_powerline_fonts = 1
" airline symbols
let g:airline_symbols.branch = ''  " Símbolos de rama
let g:airline_left_sep = ''
let g:airline_left_alt_sep = ''
let g:airline_right_sep = ''
let g:airline_right_alt_sep = ''
let g:airline_symbols.branch = ''
let g:airline_symbols.readonly = ''
let g:airline_symbols.linenr = ''

inoremap <expr> <Tab> pumvisible() ? coc#_select_confirm() : "<Tab>"


" ################ Coc.nvim ################
" Habilitar autocompletado con Coc.nvim
let g:coc_global_extensions = ['coc-tsserver', 'coc-json', 'coc-clangd', 'coc-snippets']
" Mostrar sugerencias de autocompletado mientras escribes
set completeopt=menuone,noinsert,noselect
" Comando para saltar entre los errores de LSP
nnoremap <silent> <C-]> <Plug>(coc-definition)
nnoremap <silent> <C-t> <Plug>(coc-type-definition)
nnoremap <silent> <C-i> <Plug>(coc-implementation)


" Abrir NERDTree automáticamente al iniciar Neovim
" autocmd vimenter * NERDTree
" Cerrar NERDTree si es la última ventana
autocmd BufEnter * if (winnr("$") == 1 && &filetype == "nerdtree") | quit | endif
" Asignar CTRL + N para usar múltiples cursores
nmap <C-n> :MultipleCursorsFind<CR>
" Comentar y descomentar rápidamente
nmap gc <Plug>Commentary
vmap gc <Plug>Commentary
" Abrir y cerrar Tagbar
nmap <F8> :TagbarToggle<CR>
" Uso de vim-surround para rodear texto
" Por ejemplo, para rodear una palabra con comillas: ysiw"
" Uso de vim-surround para rodear texto
" Por ejemplo, para rodear una palabra con comillas: ysiw"


