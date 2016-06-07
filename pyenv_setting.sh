echo "download pyenv"
git clone https://github.com/yyuu/pyenv.git ~/.pyenv

echo
echo "download pyenv-virtualenv"
git clone https://github.com/yyuu/pyenv-virtualenv.git ~/.pyenv/plugins/pyenv-virtualenv


if [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
    echo
    echo "install requirements for pyenv"
    sudo apt-get install -y make build-essential libssl-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev
fi

echo
echo "setting mypyenv"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

pyenv install 3.5.0
pyenv virtualenv 3.5.0 myenv3.5.0
pyenv activate myenv3.5.0
pip install -U pip
if [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
    echo "install requirements for matplotlib"
    sudo apt-get build-dep python-matplotlib
fi
pip install -r ~/.dotfiles/myenv.requirement
pyenv deactivate
