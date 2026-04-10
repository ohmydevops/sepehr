#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
   echo "Must run as root"
   exit 1
fi

# Clean previous installation
echo "Cleaning previous installation..."
systemctl stop sing-box 2>/dev/null || true
systemctl disable sing-box 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true

# Remove old configs
rm -f /etc/sing-box/config.json
rm -f /etc/nginx/sites-enabled/v2ray
rm -f /etc/nginx/sites-available/v2ray
rm -f /var/www/html/subscription.txt

# Remove old cron jobs
crontab -l 2>/dev/null | grep -v "vmess.py" | crontab - 2>/dev/null || true

echo "Installing dependencies..."
apt-get update
apt-get install -y curl python3 nginx

# Generate UUID if not provided
generate_uuid() {
    python3 -c "import uuid; print(str(uuid.uuid4()))"
}

# Prompt for configuration
echo "=== Sing Box + V2Ray VMess + Nginx Setup ==="
read -p "Enter your domain: " DOMAIN

# Auto-generate VMess ID and WebSocket path
VMESS_ID=$(generate_uuid)
WS_PATH="/$(generate_uuid)"

read -p "Enter subscription path (default: /koje): " SUB_PATH
SUB_PATH=${SUB_PATH:-/koje}

echo "Generated VMess ID: $VMESS_ID"
echo "Generated WebSocket path: $WS_PATH"
echo "Subscription link path: $SUB_PATH"

# Setup Sing Box repository
echo "Setting up Sing Box repository..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
chmod a+r /etc/apt/keyrings/sagernet.asc

echo 'Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc' | tee /etc/apt/sources.list.d/sagernet.sources

apt-get update
apt-get install -y sing-box

# Create Sing-Box config
echo "Creating Sing-Box configuration..."
mkdir -p /etc/sing-box
cat > /etc/sing-box/config.json << EOF
{
  "inbounds": [
    {
      "type": "vmess",
      "listen": "127.0.0.1",
      "listen_port": 8080,
      "users": [
        {
          "uuid": "$VMESS_ID",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "$WS_PATH"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# Create simple config file for vmess.py
echo "Creating config file..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat > "$SCRIPT_DIR/config.json" << EOF
{
  "domain": "$DOMAIN",
  "uuid": "$VMESS_ID",
  "ws_path": "$WS_PATH",
  "sub_path": "$SUB_PATH"
}
EOF

# Create subscription file
echo "Creating subscription file..."
mkdir -p /var/www/html
echo "VMess subscription will be here" > /var/www/html/subscription.txt

# Setup cron for auto-update
echo "Setting up cron job for auto-update..."
# Add cron job to update subscription every minute
(crontab -l 2>/dev/null; echo "* * * * * cd $SCRIPT_DIR && python3 vmess.py > /var/www/html/subscription.txt") | crontab -
echo "Cron job added to update subscription every minute"

# Create Nginx configuration
echo "Creating Nginx configuration..."
cat > /etc/nginx/sites-available/v2ray << EOF
server {
    listen 80;
    listen [::]:80;
    server_name *.$DOMAIN;

    location $WS_PATH {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location $SUB_PATH {
        root /var/www/html;
        try_files /subscription.txt =404;
        add_header Content-Type text/plain;
    }

    location / {
        return 404;
    }
}
EOF

# Enable nginx site
ln -sf /etc/nginx/sites-available/v2ray /etc/nginx/sites-enabled/v2ray
rm -f /etc/nginx/sites-enabled/default

# Test nginx config
if nginx -t > /dev/null 2>&1; then
    echo "Nginx configuration is valid"
    systemctl restart nginx
else
    echo "WARNING: Nginx configuration has errors"
fi

# Generate initial subscription
echo "Generating initial subscription..."
cd "$SCRIPT_DIR" && python3 vmess.py > /var/www/html/subscription.txt
echo "Initial subscription generated"

# Enable and start services
echo "Starting services..."
systemctl enable sing-box
systemctl start sing-box
systemctl enable nginx
systemctl restart nginx

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Subscription URL: https://s.$DOMAIN$SUB_PATH"
echo ""
