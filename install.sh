#!/bin/sh

echo
echo "================ Zsh setting ================"
echo "change login shell to /bin/zsh"
chsh -s /bin/zsh

echo
echo "download oh-my-zsh"
git clone https://github.com/robbyrussell/oh-my-zsh.git ~/.oh-my-zsh
echo "============================================="



echo
echo "============= Dotfiles setting ============="
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


echo
echo "=============== pyenv setting ==============="
echo "download pyenv"
git clone https://github.com/yyuu/pyenv.git ~/.pyenv

echo
echo "download pyenv-virtualenv"
git clone https://github.com/yyuu/pyenv-virtualenv.git ~/.pyenv/plugins/pyenv-virtualenv


if [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
    echo
    echo "install requirements"
    sudo apt-get install -y make build-essential libssl-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev
fi

echo
echo "setting mypyenv"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

pyenv install 3.4.3
pyenv virtualenv 3.4.3 myenv3.4.3
mypy
pip install -U pip
if [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
    sudo apt-get build-dep python-matplotlib
fi
pip install -r ~/.dotfiles/myenv.requirement
pyenv deactivate
echo "============================================="


echo
echo "restart zsh"
exec -l /bin/zsh
