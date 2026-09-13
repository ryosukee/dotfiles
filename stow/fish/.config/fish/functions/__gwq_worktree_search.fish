function __gwq_worktree_search -d 'Worktree search for current repository'
    set -l selector
    [ -n "$GHQ_SELECTOR" ]; and set selector $GHQ_SELECTOR; or set selector fzf
    set -l selector_options
    [ -n "$GHQ_SELECTOR_OPTS" ]; and set selector_options $GHQ_SELECTOR_OPTS

    if not type -qf $selector
        printf "\nERROR: '$selector' not found.\n"
        return 1
    end

    set -l query (commandline -b)
    [ -n "$query" ]; and set flags --query="$query"; or set flags

    set -l worktrees
    for line in (git worktree list --porcelain 2>/dev/null)
        if string match -q 'worktree *' -- $line
            set -a worktrees (string replace 'worktree ' '' -- $line)
        end
    end

    if test (count $worktrees) -eq 0
        printf "\nNo worktrees found.\n"
        commandline -f repaint
        return 1
    end

    switch "$selector"
        case fzf fzf-tmux peco percol fzy sk
            printf '%s\n' $worktrees | "$selector" $selector_options $flags | read select
        case '*'
            printf "\nERROR: '$selector' is not supported.\n"
    end
    [ -n "$select" ]; and cd "$select"
    commandline -f repaint
end
