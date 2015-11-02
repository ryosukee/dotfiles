#!/bin/sh

echo "change login shell to /bin/zsh"
chsh -s /bin/zsh

echo "setup oh-my-zsh"
git clone https://github.com/robbyrussell/oh-my-zsh.git ~/.oh-my-zsh

echo "setup dotfiles"
git clone https://github.com/ryosukee/dotfiles ~/.dotfiles

ln -sfv ~/.dotfiles/wedisagree_ryosuke.zsh-theme ~/.oh-my-zsh/themes/wedisagree_ryosuke.zsh-theme

for f in `ls -a ~/.dotfiles| grep "^\.[^./]"`
do
    [ "$f" = ".git" ] && continue
    ln -sfv ~/.dotfiles/$f ~/$f
done

exec /bin/zsh
