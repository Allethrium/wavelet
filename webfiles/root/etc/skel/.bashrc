# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi
# Powerline for some nicer bash prompts.
if [ -f /usr/bin/powerline-daemon ]; then
  powerline-daemon -q
  POWERLINE_BASH_CONTINUATION=1
  POWERLINE_BASH_SELECT=1
  . /usr/share/powerline/bash/powerline.sh
fi
# If not running interactively, don't do anything
[[ $- != *i* ]] && return
# If running from tty1 start sway
if [[ "$(tty)" == "/dev/tty1" ]]; then
    # https://github.com/systemd/systemd/issues/14489
    export XDG_SESSION_TYPE=wayland
    exec systemd-cat -t sway sway
fi
alias logs='cd /var/home/wavelet/logs'

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
	for rc in ~/.bashrc.d/*; do
		if [ -f "$rc" ]; then
			. "$rc"
		fi
	done
fi

unset rc