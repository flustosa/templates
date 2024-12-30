" Require git, curl
set number
" set relativenumber
set mouse=a
set autoindent
set tabstop=4
set softtabstop=4
set shiftwidth=4
set smarttab
set encoding=UTF-8
set visualbell
set scrolloff=5


call plug#begin()

Plug 'https://github.com/vim-airline/vim-airline' " Status bar
Plug 'preservim/nerdtree' " Nerd Tree
Plug 'https://github.com/tpope/vim-commentary' " For Commenting gcc & gc
Plug 'https://github.com/preservim/tagbar', {'on': 'TagbarToggle'} " Tagbar for code navigation - Require 'exuberant-ctags' apt package 
"Plug 'glepnir/dashboard-nvim' " NeoVim Dashboard
Plug 'http://github.com/tpope/vim-surround' " Surrounding ysw) // Visual mode: Select + S + 'quotation mark'
Plug 'bullets-vim/bullets.vim' " auto insert bullet points

call plug#end()

nmap <F8> :TagbarToggle<CR>
nnoremap <C-f> :NERDTreeFocus<CR>
nnoremap <C-n> :NERDTree<CR>
nnoremap <C-t> :NERDTreeToggle<CR>
nnoremap <C-l> :UndotreeToggle<CR>
