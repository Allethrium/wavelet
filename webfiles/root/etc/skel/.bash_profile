# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

# If running from tty1 start sway, sleep for five seconds and launch the UG viewer service
if [ "$(tty)" = "/dev/tty1" ]; then
	exec sway
fi
