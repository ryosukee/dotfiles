# The following lines were added by Docker Desktop to add commands to your PATH.
export PATH="$PATH:$HOME/.docker/bin"
# End of Docker Desktop section.

if [ -r "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

eval "$(mise activate bash --shims)"

if [ -r "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
