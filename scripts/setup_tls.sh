#!/bin/bash
set -e

DOMAIN="inference.patrae.net"
EMAIL="admin@patrae.net"

certbot certonly \
  --dns-route53 \
  --dns-route53-propagation-seconds 60 \
  -d "$DOMAIN" \
  --non-interactive \
  --agree-tos \
  -m "$EMAIL"

cat > /etc/nginx/conf.d/inference.conf << 'NGINXEOF'
server {
    listen 80;
    server_name inference.patrae.net;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name inference.patrae.net;
    ssl_certificate     /etc/letsencrypt/live/inference.patrae.net/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/inference.patrae.net/privkey.pem;
    client_max_body_size 50M;

    location / {
        proxy_pass         http://127.0.0.1:8000;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 600s;
    }
}
NGINXEOF

systemctl reload nginx
echo "0 0,12 * * * root certbot renew --quiet && systemctl reload nginx" \
  > /etc/cron.d/certbot-renew
echo "[ok] TLS setup complete. https://$DOMAIN"
