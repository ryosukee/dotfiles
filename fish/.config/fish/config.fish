alias ls='lsd -a -F'
alias cat='bat'
alias vim='nvim'
alias wezterm-temp='open -a WezTermTemp'
alias wezterm-temp-info='bat ~/work/temp/wezterm-dictation/README-for-ryosuke.md'

alias sshm='ssh marujirou@marujirou.local'

alias g='git'
alias gpl='git pull'
alias gps='git push'
alias gpf='git push -f'
alias gd='git def'
alias gc-='git c-'
alias gg='git-graph'

mise activate fish | source

set GHQ_SELECTOR peco
# ghq.root は git config だと ~/$HOME が展開されないためここで設定する
set -gx GHQ_ROOT "$HOME/ghq_root"

direnv hook fish | source
zoxide init fish | source

fish_add_path ~/.cargo/bin ~/.local/bin ~/.claude/bin

# The next line updates PATH for the Google Cloud SDK.
if test -f "$HOME/google-cloud-sdk/path.fish.inc"
    . "$HOME/google-cloud-sdk/path.fish.inc"
end

starship init fish | source

abbr -a claude 'claude --teammate-mode in-process'
