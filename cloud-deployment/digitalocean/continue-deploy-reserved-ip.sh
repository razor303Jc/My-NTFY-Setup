#!/bin/bash

# Continue NTFY deployment after Reserved IP assignment
set -e

RESERVED_IP="209.38.168.49"
DROPLET_ID="508876515"
DOMAIN="ntfy.razor303.co.uk"

echo "🚀 Continuing NTFY deployment with Reserved IP"
echo "==============================================="
echo "Reserved IP: $RESERVED_IP"
echo "Droplet ID: $DROPLET_ID"
echo "Domain: $DOMAIN"
echo ""

# Update droplet-info.txt with the Reserved IP
cat > droplet-info.txt << EOF
Droplet ID: $DROPLET_ID
Droplet Name: ntfy-server
IP Address: $RESERVED_IP
Reserved IP: $RESERVED_IP
Size: s-1vcpu-1gb
Region: lon1
SSH Key: 49388495
Created: $(date)
EOF

echo "📝 Updated droplet-info.txt with Reserved IP: $RESERVED_IP"

# Test SSH connectivity
echo "🔍 Testing SSH connectivity to Reserved IP..."
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$RESERVED_IP 'echo "SSH connection successful"' 2>/dev/null; then
    echo "✅ SSH connection to $RESERVED_IP successful!"
else
    echo "❌ SSH connection failed. Please check:"
    echo "   1. Reserved IP is properly assigned to the droplet"
    echo "   2. Network connectivity"
    echo "   3. Firewall settings"
    exit 1
fi

# Continue with server setup
echo "⚙️  Continuing server setup..."

# Create setup script for the server
cat > setup-server.sh << 'EOF'
#!/bin/bash
set -e

echo "🔧 Setting up NTFY server..."

# Update system
apt update && apt upgrade -y

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
fi

# Install Docker Compose if not already installed
if ! command -v docker-compose &> /dev/null; then
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Install other tools
apt install -y ufw fail2ban

# Setup firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80
ufw allow 443
ufw --force enable

# Create ntfy user if it doesn't exist
if ! id -u ntfy &>/dev/null; then
    useradd -m -s /bin/bash ntfy
    usermod -aG docker ntfy
fi

# Create directories
mkdir -p /opt/ntfy
chown ntfy:ntfy /opt/ntfy

echo "✅ Server setup complete!"
EOF

# Run server setup
echo "📡 Running server setup on $RESERVED_IP..."
scp -o StrictHostKeyChecking=no setup-server.sh root@$RESERVED_IP:/tmp/
ssh -o StrictHostKeyChecking=no root@$RESERVED_IP 'bash /tmp/setup-server.sh'

# Deploy NTFY
echo "🚀 Deploying NTFY application..."

# Copy the simple docker-compose file
scp -o StrictHostKeyChecking=no docker-compose.simple.yml ntfy@$RESERVED_IP:/opt/ntfy/docker-compose.yml

# Start NTFY
ssh -o StrictHostKeyChecking=no ntfy@$RESERVED_IP << 'EOF'
cd /opt/ntfy
mkdir -p ntfy-cache ntfy-data

# Start NTFY
docker-compose up -d

echo "✅ NTFY deployment complete!"
EOF

echo ""
echo "🎉 NTFY deployment successful!"
echo "==============================="
echo "Server IP: $RESERVED_IP"
echo "HTTP URL: http://$RESERVED_IP:8080"
echo "Domain URL: http://$DOMAIN:8080 (once DNS propagates)"
echo ""
echo "Next steps:"
echo "1. Check DNS: ./check-dns.sh"
echo "2. Test HTTP: curl -I http://$RESERVED_IP:8080"
echo "3. Deploy SSL: ./setup-ssl.sh"
echo ""
echo "Management commands:"
echo "• SSH to server: ssh ntfy@$RESERVED_IP"
echo "• View logs: ssh ntfy@$RESERVED_IP 'cd /opt/ntfy && docker-compose logs -f'"
echo "• Restart: ssh ntfy@$RESERVED_IP 'cd /opt/ntfy && docker-compose restart'"
