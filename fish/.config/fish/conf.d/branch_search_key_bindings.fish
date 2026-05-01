function gbranch
  git branch -a --sort=-authordate |
  grep -v -e '->' -e '*' |
  perl -pe 's/^\h+//g' |
  perl -pe 's#^remotes/origin/###' |
  perl -nle 'print if !$c{$_}++' |
  fzf |
  xargs git checkout
  commandline -f repaint
end

bind \cg 'gbranch'
if bind -M insert >/dev/null 2>/dev/null
    bind -M insert \cg 'gbranch'
end
