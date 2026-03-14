#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
   echo "Must run as root"
   exit 1
fi

# Clean previous installation
echo "Cleaning previous installation..."
systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true

# Remove old configs
rm -f /usr/local/etc/xray/config.json
rm -f /etc/nginx/sites-enabled/v2ray
rm -f /etc/nginx/sites-available/v2ray
rm -f /var/www/html/subscription.txt

# Remove old cron jobs
crontab -l 2>/dev/null | grep -v "cloudfront.py" | crontab - 2>/dev/null || true

echo "Installing dependencies..."
apt-get update
apt-get install -y curl python3 nginx

# Generate UUID if not provided
generate_uuid() {
    python3 -c "import uuid; print(str(uuid.uuid4()))"
}

# Prompt for configuration
echo "=== Xray + Trojan + Nginx Setup (CloudFront) ==="
read -p "Enter your domain: " DOMAIN

# Auto-generate Trojan password and XHTTP path
TROJAN_PASSWORD=$(generate_uuid)
XHTTP_PATH="/$(generate_uuid)"

read -p "Enter subscription path (default: /koje): " SUB_PATH
SUB_PATH=${SUB_PATH:-/koje}

echo "Generated Trojan password: $TROJAN_PASSWORD"
echo "Generated XHTTP path: $XHTTP_PATH"
echo "Subscription link path: $SUB_PATH"

# Install Xray-core
echo "Installing Xray-core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Create Xray config
echo "Creating Xray configuration..."
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json << EOF
{
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 8080,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "$TROJAN_PASSWORD"
          }
        ]
      },
      "streamSettings": {
        "network": "httpupgrade",
        "httpupgradeSettings": {
          "path": "$XHTTP_PATH",
          "host": "$DOMAIN"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# Create simple config file for cloudfront.py
echo "Creating config file..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat > "$SCRIPT_DIR/config.json" << EOF
{
  "domain": "$DOMAIN",
  "password": "$TROJAN_PASSWORD",
  "xhttp_path": "$XHTTP_PATH",
  "sub_path": "$SUB_PATH"
}
EOF

# Create subscription file
echo "Creating subscription file..."
mkdir -p /var/www/html
echo "Trojan subscription will be here" > /var/www/html/subscription.txt

# Setup cron for auto-update
echo "Setting up cron job for auto-update..."
# Add cron job to update subscription every minute
(crontab -l 2>/dev/null; echo "* * * * * cd $SCRIPT_DIR && python3 cloudfront.py > /var/www/html/subscription.txt") | crontab -
echo "Cron job added to update subscription every minute"

# Create Nginx configuration
echo "Creating Nginx configuration..."
cat > /etc/nginx/sites-available/v2ray << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location $XHTTP_PATH {
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
cd "$SCRIPT_DIR" && python3 cloudfront.py > /var/www/html/subscription.txt
echo "Initial subscription generated"

# Enable and start services
echo "Starting services..."
systemctl enable xray
systemctl start xray
systemctl enable nginx
systemctl restart nginx

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Subscription URL: https://$DOMAIN$SUB_PATH"
echo ""
