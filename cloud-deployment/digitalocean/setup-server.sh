#!/bin/bash
set -e

# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl enable docker
systemctl start docker

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install other tools
apt install -y nginx certbot python3-certbot-nginx ufw fail2ban

# Setup firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80
ufw allow 443
ufw --force enable

# Create ntfy user
useradd -m -s /bin/bash ntfy
usermod -aG docker ntfy

# Create directories
mkdir -p /opt/ntfy
chown ntfy:ntfy /opt/ntfy

echo "Server setup complete!"
