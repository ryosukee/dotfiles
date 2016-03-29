"#####表示設定#####
syntax on
set encoding=utf-8
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
set listchars=tab:»-,trail:-,extends:»,precedes:«,nbsp:%,eol:↲

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

"#####拡張子の登録#####
augroup PrevimSettings
    autocmd!
    autocmd BufNewFile,BufRead *.{md,mdwn,mkd,mkdn,mark*} set filetype=markdown
augroup END

"#####file type毎の設定#####
autocmd FileType scheme setlocal shiftwidth=2 tabstop=2
autocmd FileType html setlocal shiftwidth=2 tabstop=2

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

function! refresh()
    while 1
        e
        redr
    endwhile


"nmap <F5> :!/usr/bin/python %<CR>
"nmap <F12> :!/usr/lib/python2.7/pdb.py %<CR>


"#####その他設定#####
set noswapfile  " .swapファイルを作らない
set matchpairs& matchpairs+=<:> " 対応括弧に'<'と'>'のペアを追加



"---------------------------
" Start Neobundle Settings.
"---------------------------
" bundleで管理するディレクトリを指定
set runtimepath+=~/.vim/bundle/neobundle.vim/

" Required:
call neobundle#begin(expand('~/.vim/bundle/'))

" neobundle自体をneobundleで管理
NeoBundleFetch 'Shougo/neobundle.vim'

" previm (Markdownのpreview)
NeoBundle 'kannokanno/previm'
let g:previm_open_cmd = 'open -a Safari'
let g:previm_enable_realtime = 1
"let g:previm_disable_default_css = 1
"let g:previm_custom_css_path = '/Users/ryosuke/test.css'

" vim-markdown (markdown syntax)
NeoBundle 'plasticboy/vim-markdown'
let g:vim_markdown_no_default_key_mappings = 1

" vim-niji
NeoBundle 'vim-scripts/vim-niji'
let g:niji_matching_filetypes = ['lisp', 'scheme', 'clojure', 'ruby', 'python']

" vimproc.vim
NeoBundle 'Shougo/vimproc.vim', {
            \ 'build' : {
            \     'windows' : 'tools\\update-dll-mingw',
            \     'cygwin' : 'make -f make_cygwin.mak',
            \     'mac' : 'make -f make_mac.mak',
            \     'linux' : 'make',
            \     'unix' : 'gmake',
            \    },
            \ }

" neocomplete.vim
" NeoBundle 'Shougo/neocomplete'

" neosnippet.vim
NeoBundle 'Shougo/neosnippet.vim'
NeoBundle 'Shougo/neosnippet-snippets'
imap <C-k> <Plug>(neosnippet_expand_or_jump)
smap <C-k> <Plug>(neosnippet_expand_or_jump)
xmap <C-k> <Plug>(neosnippet_expand_target)
let g:neosnippet#snippets_directory='~/.vim/mysnippets'

" unite.vim
" NeoBundle 'Shougo/unite.vim'

" gauche
NeoBundle 'aharisu/vim_goshrepl'
NeoBundle 'aharisu/vim-gdev'
"let g:neocomplcache_keyword_patterns['gosh-repl'] = "[[:alpha:]+*/@$_=.!?-][[:alnum:]+*/@$_:=.!?-]*"
vmap <C-g> <Plug>(gosh_repl_send_block)

" syntastic
NeoBundle 'scrooloose/syntastic'
let g:syntastic_python_checkers = ['flake8']
let g:syntastic_python_flake8_args = '--ignore="D100"'

" vim-autopep8
NeoBundle 'tell-k/vim-autopep8'

" jedi-vim
 NeoBundle 'davidhalter/jedi-vim'
" docstringは表示しない
autocmd FileType python setlocal completeopt-=preview

" Yggdroot/indentLine
NeoBundle 'Yggdroot/indentLine'
let g:indentLine_color_term = 239
let g:indentLine_char = '|'
let g:indentLine_faster = 1
nmap <silent><Leader>i :<C-u>IndentLinesToggle<CR>

call neobundle#end()

" Required:
filetype plugin indent on

" 未インストールのプラグインがある場合、インストールするかどうかを尋ねてくれるようにする設定
" 毎回聞かれると邪魔な場合もあるので、この設定は任意です。
NeoBundleCheck

"-------------------------
" End Neobundle Settings.
"-------------------------

