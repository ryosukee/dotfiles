# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="wedisagree_ryosuke"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git)

# User configuration

export PATH=$HOME/bin:/usr/local/bin:$PATH
# export MANPATH="/usr/local/man:$MANPATH"

source $ZSH/oh-my-zsh.sh

function ph(){
    local prompt_descriptions
    prompt_descriptions=(
        $ZSH_THEME_GIT_PROMPT_DIRTY 'dirty\tclean でない'
        $ZSH_THEME_GIT_PROMPT_UNTRACKED 'untracked\tトラックされていないファイルがある'
        $ZSH_THEME_GIT_PROMPT_CLEAN 'clean'
        $ZSH_THEME_GIT_PROMPT_ADDED 'added\t追加されたファイルがある'
        $ZSH_THEME_GIT_PROMPT_MODIFIED 'modified\t変更されたファイルがある'
        $ZSH_THEME_GIT_PROMPT_DELETED 'deleted\t削除されたファイルがある'
        $ZSH_THEME_GIT_PROMPT_RENAMED 'renamed\tファイル名が変更されたファイルがある'
        $ZSH_THEME_GIT_PROMPT_UNMERGED 'unmerged\tマージされていないファイルがある'
        $ZSH_THEME_GIT_PROMPT_AHEAD 'ahead\tmaster リポジトリよりコミットが進んでいる'
    )

    local i
    for ((i = 1; i <= $#prompt_descriptions; i += 2))
    do
        local p=$prompt_descriptions[$i]
        local d=$prompt_descriptions[$i+1]
        echo `echo $p | sed -E 's/%.| //g'` $reset_color $d
    done
}


# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/dsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"




# my zshrc
# 濁点半濁点をちゃんと表示
setopt combining_chars

# missったときに, もしかして
setopt correct

# 直前と同じコマンドをヒストリに追加しない
setopt hist_ignore_dups

# cdしたあとで、自動的に ls する
#function chpwd() { ls }

if [ "$(uname)" = "Darwin" ]; then
# mac ports
#    PATH=/opt/local/bin:/opt/local/sbin:$PATH
#    PATH=/opt/local/libexec/word2vec:$PATH

# java
    export JAVA_HOME=`/System/Library/Frameworks/JavaVM.framework/Versions/A/Commands/java_home -v "1.8"`
    alias java_home='/System/Library/Frameworks/JavaVM.framework/Versions/A/Commands/java_home'
fi


# alias
alias sudo='sudo '
if [ "$(uname)" = "Darwin" ]; then
    alias rm='rmtrash'
    alias ls='ls -G -F'
elif [ "$(expr substr $(uname -s) 1 5)" = 'Linux' ]; then
    alias rm='trash-put'
    alias ls='ls --color=auto -F'
fi
alias ipy='ipython --colors=linux'
alias jupyslide='jupyter nbconvert $1 --to slides --post serve'
alias jupypy='jupyter nbconvert $1 --to=python'
alias jupy='jupyter notebook'
alias mypy='pyenv activate myenv3.5.0'
alias pipall='pip freeze --local | grep -v "^\-e" | cut -d = -f 1 | xargs -n1 pip install -U'
alias pushdots='bash ~/.dotfiles/push_dotfiles.sh'
alias pulldots='git -C ~/.dotfiles pull'
alias sshwin='ssh ryosuke@192.168.0.7 -o PreferredAuthentications=password'
alias t='bash ~/MyGlobalScripts/tweet.sh'
alias weather='curl -4 wttr.in/Tokyo'
alias jnethack='cocot -t UTF-8 -p EUC-JP -- jnethack'
alias vim='nvim'
function line() {
    head -n $1 $2 | tail -n 1
}
# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
export PYENV_VIRTUALENV_DISABLE_PROMPT=1
mypy

# Rust
source ${HOME}/.cargo/env

# phpenv
export PHPENV_ROOT=$HOME/.phpenv
export PATH="$HOME/.phpenv/bin:$PATH"
eval "$(phpenv init -)"

# std error coloer
zmodload zsh/terminfo zsh/system
color_stderr() {
  while sysread std_err_color; do
    syswrite -o 2 "${fg_bold[red]}${std_err_color}${terminfo[sgr0]}"
  done
}
exec 2> >(color_stderr)

pyenv activate crypto3.5.2
