for f in `ls -a ~/.dotfiles| grep "^\.[^./]"`
do
    [ "$f" = ".git" ] && continue
    sudo rm ~/$f
done
sudo rm -r ~/.dotfiles
sudo rm -r ~/.oh-my-zsh
sudo rm -r ~/.pyenv
chsh -s /bin/bash
