#!/bin/sh

echo "change login shell to /bin/zsh"
chsh -s /bin/zsh

echo "setup oh-my-zsh"
git clone https://github.com/robbyrussell/oh-my-zsh ~/.oh-my-zsh

echo "setup dotfiles"
git clone https://github.com/ryosukee/dotfiles ~/.dotfiles

ln -sfv ~/.dotfiles/wedisagree_ryosuke.zsh-theme ~/.oh-my-zsh/themes/wedisagree_ryosuke.zsh-theme

cd ~/.dotfiles
for f in `ls -a | grep "^\.[^./]"`
do
    [ "$f" = ".git" ] && continue
    ln -sfv $f ../$f
done
cd
