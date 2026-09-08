# claude の abbr 展開。ディレクトリ固有の引数は __claude_abbr_local_args に委ねる。
# その関数は stow 管理外の conf.d に置く (private repo のパスを public な dotfiles に入れないため)。
function __claude_abbr --description 'claude abbr の展開'
    set -l parts claude --dangerously-skip-permissions
    if functions -q __claude_abbr_local_args
        set -a parts (__claude_abbr_local_args)
    end
    string join ' ' -- $parts
end
