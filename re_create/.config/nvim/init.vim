set number
set showmatch
"set smartindent
set tabstop=4
set shiftwidth=4
set expandtab
set cursorline
set laststatus=2
set list                " 不可視文字の可視化
" デフォルト不可視文字は美しくないのでUnicodeで綺麗に
" set listchars=tab:»-,trail:-,extends:»,precedes:«,nbsp:%,eol:↲
set listchars=tab:»-,trail:-,extends:»,precedes:«,nbsp:%

"####表示色設定#####
execute "set colorcolumn=" . join(range(80, 9999), ',')
autocmd ColorScheme * highlight ColorColumn ctermbg=235
autocmd ColorScheme * highlight LineNr ctermbg=235 ctermfg=242
autocmd ColorScheme * highlight CursorLineNr ctermbg=239 ctermfg=246
autocmd ColorScheme * highlight Visual ctermbg=239 ctermfg=246
colorscheme desert

"#####操作設定#####
set shiftround " '<'や'>'でインデントする際に'shiftwidth'の倍数に丸める
set backspace=indent,eol,start "バックスペースで消せるように

"#####検索設定#####
set ignorecase "大文字/小文字の区別を無視
set smartcase "検索文字に大文字が含まれている場合は区別
set wrapscan "最後まで検索したら最初に戻る
set hlsearch "ハイライト

"#####キーマップ#####
"カーソルを表示行単位で移動する
nnoremap j gj
nnoremap k gk
"ESC2回でnoh
nnoremap <ESC><ESC> :nohlsearch<CR>
"relativenumberとnumberをトグル表示
if version >= 703
    nnoremap  <silent> ,n :<C-u>ToggleNumber<CR>
    command! -nargs=0 ToggleNumber call ToggleNumberOption()

    function! ToggleNumberOption()
        if &number
            set relativenumber
            set nonumber
        else
            set number
            set norelativenumber
        endif
    endfunction
endif

command! Refresh call Refresh()
function! Refresh()
    while 1
        e
        redr
    endwhile
endfunction


"#####その他設定#####
set noswapfile  " .swapファイルを作らない
set matchpairs& matchpairs+=<:> " 対応括弧に'<'と'>'のペアを追加


"##### vim plugin #####
if has('vim_starting')
  set rtp+=~/.local/share/nvim/plugged
  if !isdirectory(expand('~/.local/share/nvim/plugged'))
    echo 'install vim-plug...'
    call system('mkdir -p ~/.local/share/nvim/plugged')
    call system('git clone https://github.com/junegunn/vim-plug.git ~/.local/share/nvim/plugged/autoload')
  end
endif

call plug#begin('~/.local/share/nvim/plugged')
" vim-niji
Plug 'vim-scripts/vim-niji'
let g:niji_matching_filetypes = ['lisp', 'scheme', 'clojure', 'ruby', 'python']

if has('job') && has('channel') && has('timers')
  " ALE
  Plug 'w0rp/ale'
"  let g:ale_lint_on_enter = 0
else
  " syntastic
  Plug 'vim-syntastic/syntastic'
  let g:syntastic_python_checkers = ['flake8']
  let g:syntastic_python_flake8_args = '--ignore="D100"'
endif

" vim-autopep8
Plug 'tell-k/vim-autopep8'

" jedi-vim
Plug 'davidhalter/jedi-vim'
" docstringは表示しない
autocmd FileType python setlocal completeopt-=preview

" indentLine
Plug 'Yggdroot/indentLine'
let g:indentLine_color_term = 239
let g:indentLine_char = '|'
let g:indentLine_faster = 1
nmap <silent><Leader>i :<C-u>IndentLinesToggle<CR>

" git diff
Plug 'airblade/vim-gitgutter'
set updatetime=250

" 末尾のスペースハイライト (:FixWhitespace で全て削除)
Plug 'bronson/vim-trailing-whitespace'

" vim-ariline
Plug 'vim-airline/vim-airline'

" nerd-tree
Plug 'scrooloose/nerdtree'
map <C-n> :NERDTreeToggle<CR>

" git
Plug 'tpope/vim-fugitive'

call plug#end()
