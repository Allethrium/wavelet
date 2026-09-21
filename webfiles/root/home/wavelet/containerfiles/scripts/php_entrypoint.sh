#!/bin/sh

# Note the container is designed to run in the http-php pod with appropriate volume mounts
# Without these, the watch and core_processor will be unable to start

# Start CLI daemons in background
(
  while true; do
    php /var/www/html/etcd_watch.php
    echo "$(date) [entrypoint] etcd_watch exited (code $?), restarting in 2s" >&2
    sleep 2
  done
) &

# Foreground = PHP-FPM (what systemd/podman waits on)
exec php-fpm --nodaemonize