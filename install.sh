#!/usr/bin/sh

for f in .??*
do
    [ "$f" = ".git" ] && continue

    ln -sv "$f" "$HOME"/"$f"
done
