#!/bin/sh

# Note the container is designed to run in the http-php pod with appropriate volume mounts
# Without these, the watch and core_processor will be unable to start

# Start CLI daemons in background
php /var/www/html/etcd_watch.php &

# Foreground = PHP-FPM (what systemd/podman waits on)
exec php-fpm --nodaemonize