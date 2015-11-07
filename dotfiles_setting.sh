echo "create symbolic link of dotfiles"
ln -sfv ~/.dotfiles/wedisagree_ryosuke.zsh-theme ~/.oh-my-zsh/themes/wedisagree_ryosuke.zsh-theme
for f in `ls -a ~/.dotfiles| grep "^\.[^./]"`
do
    [ "$f" = ".git" ] && continue
    ln -sfv ~/.dotfiles/$f ~/$f
done
