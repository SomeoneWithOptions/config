#!/usr/bin/env bash

set -euo pipefail

if ! command -v git >/dev/null 2>&1; then
    printf 'git is required before running this script.\n' >&2
    exit 1
fi

git config --global user.email "andrescastesol@gmail.com"
git config --global user.name "SomeoneWithOptions"
git config --global alias.cp '!f() { git add . && git commit -m "$1" && git push; }; f'
git config --global alias.s 'log -15 --oneline'
git config --global alias.ac '!git add . && git commit -m'
git config --global alias.c 'commit -m'
git config --global alias.r 'reset --hard HEAD'

printf 'Git config updated idempotently: %s\n' "${HOME}/.gitconfig"
