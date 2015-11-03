#!/bin/sh

echo "================ Zsh setting ================"
echo
echo "change login shell to /bin/zsh"
chsh -s /bin/zsh

echo
echo "download oh-my-zsh"
git clone https://github.com/robbyrussell/oh-my-zsh.git ~/.oh-my-zsh
echo "============================================="



echo "============= Dotfiles setting ============="
echo
echo "download dotfiles"
git clone https://github.com/ryosukee/dotfiles ~/.dotfiles

echo
echo "create symbolic link of dotfiles"
ln -sfv ~/.dotfiles/wedisagree_ryosuke.zsh-theme ~/.oh-my-zsh/themes/wedisagree_ryosuke.zsh-theme
for f in `ls -a ~/.dotfiles| grep "^\.[^./]"`
do
    [ "$f" = ".git" ] && continue
    ln -sfv ~/.dotfiles/$f ~/$f
done
echo "============================================="


echo "=============== pyenv setting ==============="
echo
echo "download pyenv"
git clone https://github.com/yyuu/pyenv.git ~/.pyenv

echo
echo "download pyenv-virtualenv"
git clone https://github.com/yyuu/pyenv-virtualenv.git ~/.pyenv/plugins/pyenv-virtualenv

echo
echo "setting mypyenv"
source ~/.zshrc
pyenv install 3.4.3
pyenv virtualenv 3.4.3 myenv3.4.3
mypy
if [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
    sudo apt-get build-dep python-matplotlib
fi
pip install -r ~/.dotfiles/myenv.requirement
pyenv deactivate
echo "============================================="


echo
echo "restart zsh"
exec -l /bin/zsh
