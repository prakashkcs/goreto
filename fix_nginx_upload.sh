#!/bin/bash
# Fix Nginx upload size limit for Goreto app
# Run this on your VPS server as root

# Add client_max_body_size to nginx.conf http block
if ! grep -q "client_max_body_size" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \    client_max_body_size 500M;' /etc/nginx/nginx.conf
    echo "Added client_max_body_size to nginx.conf"
fi

# Add to all site configs
for conf in /etc/nginx/sites-enabled/*; do
    if [ -f "$conf" ]; then
        if ! grep -q "client_max_body_size" "$conf"; then
            sed -i '/server {/a \        client_max_body_size 500M;' "$conf"
            echo "Added client_max_body_size to $conf"
        fi
    fi
done

# Test nginx config
nginx -t

# Reload nginx if test passed
if [ $? -eq 0 ]; then
    systemctl reload nginx
    echo "Nginx reloaded successfully"
else
    echo "Nginx config test failed - please check manually"
fi

echo "Done! Upload limit set to 500MB"
