#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -q >/dev/null 2>&1
apt-get install -y -q nginx certbot python3-certbot-nginx openssl >/dev/null 2>&1

mkdir -p /etc/nginx/ssl /etc/nginx/snippets /var/www/letsencrypt

# --- self-signed cert (interim) ---
if [ ! -f /etc/nginx/ssl/healthflow-selfsigned.crt ]; then
  openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/healthflow-selfsigned.key \
    -out /etc/nginx/ssl/healthflow-selfsigned.crt \
    -subj "/C=EG/ST=Cairo/L=Cairo/O=HealthFlow/OU=NDP/CN=healthflow.eg" \
    -addext "subjectAltName=DNS:healthflow.eg,DNS:registry.healthflow.eg,DNS:keycloak.healthflow.eg,DNS:api.sunbird.healthflow.eg,DNS:sunbird.healthflow.eg,DNS:admin.healthflow.eg,IP:146.190.204.129"
fi

# --- ssl params snippet ---
cat > /etc/nginx/snippets/ssl-params.conf <<'EOF'
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options SAMEORIGIN always;
EOF

# --- proxy params snippet ---
cat > /etc/nginx/snippets/proxy-params.conf <<'EOF'
proxy_http_version 1.1;
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host  $host;
proxy_set_header Upgrade           $http_upgrade;
proxy_set_header Connection        "upgrade";
proxy_connect_timeout 60s;
proxy_send_timeout    60s;
proxy_read_timeout    60s;
proxy_buffering off;
EOF

# --- site config ---
cp /root/healthflow-nginx.conf /etc/nginx/sites-available/healthflow.conf
ln -sf /etc/nginx/sites-available/healthflow.conf /etc/nginx/sites-enabled/healthflow.conf
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable nginx >/dev/null 2>&1
systemctl restart nginx
echo "NGINX_SETUP_DONE"
systemctl is-active nginx
