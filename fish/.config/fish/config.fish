alias ls='lsd -a -F'
alias cat='bat'
alias vim='nvim'

alias sshm='ssh marujirou@marujirou.local'

alias g='git'
alias gpl='git pull'
alias gps='git push'
alias gpf='git push -f'
alias gd='git def'
alias gc-='git c-'
alias gg='git-graph'

mise activate fish | source

set GHQ_SELECTOR fzf
# ghq.root は git config だと ~/$HOME が展開されないためここで設定する
set -gx GHQ_ROOT "$HOME/ghq_root"

# claude-pages (cc-tools の claude-user-communication plugin) の配置先と配信 URL
# 配信のセットアップは docs/tailscale.md 参照
set -gx CLAUDE_PAGES_DIR "$HOME/.local/share/claude-pages"
set -gx CLAUDE_PAGES_BASE_URL "https://mac-mini.hake-tarpon.ts.net"

direnv hook fish | source
zoxide init fish | source

fish_add_path ~/.cargo/bin ~/.local/bin ~/.claude/bin

# The next line updates PATH for the Google Cloud SDK.
if test -f "$HOME/google-cloud-sdk/path.fish.inc"
    . "$HOME/google-cloud-sdk/path.fish.inc"
end

starship init fish | source

abbr -a claude 'claude --teammate-mode in-process' --dangerously-skip-permissions
