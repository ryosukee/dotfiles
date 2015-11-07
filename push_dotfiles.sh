message=$@
if [ "${message}" = "" ]; then
    echo 'message is required'
else
    cd ~/.dotfiles
    git add --all
    git commit -m "${message}"
    git push
    cd -
fi
