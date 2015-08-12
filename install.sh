#!/bin/sh

for f in .??*
do
    [ "$f" = ".git" ] && continue
    cd
    ln -sv "dotfiles/$f" "$f"
    cd -
done

cd
ln -sv dotfiles/wedisagree_ryosuke.zsh-theme ./.oh-my-zsh/themes/wedisagree_ryosuke.zsh-theme

