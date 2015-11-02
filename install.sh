#!/bin/sh

echo "change login shell to /bin/zsh"
chsh /bin/zsh

echo "setup oh-my-zsh"
sh -c "$(wget https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"

echo "setup dotfiles"
git clone https://github.com/ryosukee/dotfiles ~/.dotfiles

ln -sfv ~/dotfiles/wedisagree_ryosuke.zsh-theme ~/.oh-my-zsh/themes/wedisagree_ryosuke.zsh-theme

for f in `ls -a | grep "^\.[^./]"`
do
    [ "$f" = ".git" ] && continue
    ln -sfv "~/dotfiles/$f" "~/$f"
done

