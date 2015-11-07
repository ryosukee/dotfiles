#!/bin/sh

echo
echo "============= Dotfiles setting ============="
echo "download dotfiles"
git clone https://github.com/ryosukee/dotfiles ~/.dotfiles

sh ~/.dotfiles/dotfiles_setting.sh
echo "============================================="


echo
echo "================ Zsh setting ================"
sh ~/.dotfiles/zsh_setting.sh
echo "============================================="


echo
echo "=============== pyenv setting ==============="
sh ~/.dotfiles/pyenv_setting.sh
echo "============================================="


echo
echo "=============== vim setting ================="
sh ~/.dotfiles/vim_setting.sh
echo "============================================="


echo
echo "restart zsh"
exec -l /bin/zsh
