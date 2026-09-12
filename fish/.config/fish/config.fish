abbr -a ls lsd -a -F
abbr -a cat bat
abbr -a vim nvim

abbr -a pbc pbcopy

abbr -a sshm ssh marujirou@marujirou.local

abbr -a g git
abbr -a gpl git pull
abbr -a gps git push
abbr -a gpf git push -f
abbr -a gd git def
abbr -a gg git-graph

abbr -a claude --function __claude_abbr
abbr -a codex codex --profile dotfiles --dangerously-bypass-approvals-and-sandbox

mise activate fish | source

set GHQ_SELECTOR fzf
# ghq.root は git config だと ~/$HOME が展開されないためここで設定する
set -gx GHQ_ROOT "$HOME/ghq_root"

# yazi や git は EDITOR が無いと vi (= /usr/bin/vim) に落ちる
set -gx EDITOR nvim

direnv hook fish | source
zoxide init fish | source

fish_add_path ~/.cargo/bin ~/.local/bin ~/.claude/bin

# The next line updates PATH for the Google Cloud SDK.
if test -f "$HOME/google-cloud-sdk/path.fish.inc"
    . "$HOME/google-cloud-sdk/path.fish.inc"
end

starship init fish | source
