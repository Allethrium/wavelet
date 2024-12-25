# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

# If running from tty1, start nginx web UI service and start sway after a five second delay
if [ "$(tty)" = "/dev/tty1" ]; then
	if [[ $(hostname) == *"svr"* ]]; then
		systemctl --user start http-php-pod.service
	fi
	sleep 1
	exec sway
fi
