function fzf_select_history
  if test (count $argv) = 0
    set fzf_flags --layout=reverse
  else
    set fzf_flags --layout=reverse --query "$argv"
  end

  history | fzf $fzf_flags | read foo

  if [ $foo ]
    commandline $foo
  else
    commandline ''
  end
end
