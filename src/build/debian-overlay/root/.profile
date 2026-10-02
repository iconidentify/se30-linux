# ~/.profile: login shells (Debian's runs mesg, which is slow to start here)
if [ -n "${BASH-}" ] && [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
