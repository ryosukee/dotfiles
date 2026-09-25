if [ -r "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

eval "$(mise activate bash --shims)"

if [ -r "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
