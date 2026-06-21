#!/bin/sh
# This script is called from the project root by devcontainer.json.

set -eu

# Git can report bind-mounted repositories as dubious ownership inside the container.
git config --global --add safe.directory "$(pwd -P)"

printf 'Lua: '
lua5.1 -v

printf 'Luacheck: '
luacheck --version

printf 'StyLua: '
stylua --version

printf 'Lua language server: '
lua-language-server --version
