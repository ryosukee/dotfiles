echo "download dotfiles"
git clone https://github.com/ryosukee/dotfiles.git ~/.dotfiles

echo
echo "================ Zsh setting ================"
bash ~/.dotfiles/zsh_setting.sh
echo "============================================="


echo
echo "============= Dotfiles setting ============="
bash ~/.dotfiles/dotfiles_setting.sh
echo "============================================="


echo
echo "=============== pyenv setting ==============="
bash ~/.dotfiles/pyenv_setting.sh
echo "============================================="


echo
echo "=============== vim setting ================="
bash ~/.dotfiles/vim_setting.sh
echo "============================================="


echo
echo "restart zsh"
exec -l /bin/zsh
