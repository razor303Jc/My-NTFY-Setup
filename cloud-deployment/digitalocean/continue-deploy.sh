#!/bin/bash

# Continue NTFY deployment after system is ready
# This script resumes deployment from where it left off

set -e

# Load droplet info
if [ ! -f "droplet-info.txt" ]; then
    echo "❌ droplet-info.txt not found. Run ./deploy.sh first"
    exit 1
fi

# Extract droplet IP
DROPLET_IP=$(grep "IP Address:" droplet-info.txt | cut -d' ' -f3)

echo "🚀 Continuing NTFY deployment..."
echo "Droplet IP: $DROPLET_IP"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

setup_server() {
    print_status "Setting up the server..."
    
    # Create setup script
    cat > setup-server.sh << 'EOF'
#!/bin/bash
set -e

echo "Starting server setup..."

# Wait for any background apt processes to finish
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    echo "Waiting for apt lock to be released..."
    sleep 10
done

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
EOF

    # Copy and run setup script
    print_status "Copying setup script to server..."
    scp -o StrictHostKeyChecking=no setup-server.sh root@$DROPLET_IP:/tmp/
    
    print_status "Running server setup (this may take a few minutes)..."
    ssh -o StrictHostKeyChecking=no root@$DROPLET_IP 'bash /tmp/setup-server.sh'
    
    print_status "Server setup complete!"
}

deploy_ntfy() {
    print_status "Deploying NTFY configuration..."
    
    # Copy deployment files
    print_status "Copying NTFY files to server..."
    scp -o StrictHostKeyChecking=no -r ../* ntfy@$DROPLET_IP:/opt/ntfy/
    
    # Deploy NTFY
    print_status "Starting NTFY services..."
    ssh -o StrictHostKeyChecking=no ntfy@$DROPLET_IP << 'EOF'
cd /opt/ntfy
mkdir -p ntfy-cache ntfy-data ssl

# Start NTFY
docker-compose -f docker-compose.production.yml up -d

echo "NTFY services started!"
EOF

    print_status "NTFY deployment complete!"
}

configure_ssl() {
    if [ "$1" = "--with-ssl" ]; then
        print_status "Setting up SSL certificate..."
        
        echo "Enter your domain name (e.g., ntfy.yourdomain.com):"
        read -r DOMAIN
        
        if [ -z "$DOMAIN" ]; then
            print_error "Domain name is required for SSL setup"
            return 1
        fi
        
        ssh -o StrictHostKeyChecking=no ntfy@$DROPLET_IP << EOF
# Configure Nginx
sudo cp /opt/ntfy/nginx.conf /etc/nginx/sites-available/ntfy
sudo sed -i 's/your-domain.com/$DOMAIN/g' /etc/nginx/sites-available/ntfy
sudo ln -sf /etc/nginx/sites-available/ntfy /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

# Get SSL certificate
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN

echo "SSL certificate configured for $DOMAIN"
EOF
        
        print_status "SSL setup complete!"
        echo ""
        echo "🎉 Your NTFY server is ready at: https://$DOMAIN"
        
    else
        echo ""
        echo "🎉 Your NTFY server is ready at: http://$DROPLET_IP:8080"
        echo ""
        echo "To set up SSL, run: $0 --with-ssl"
    fi
}

# Run deployment steps
setup_server
deploy_ntfy
configure_ssl $1

echo ""
echo "✅ Deployment completed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Configure DNS to point to $DROPLET_IP"
echo "2. Test your notifications"
echo "3. Set up authentication if needed"
echo ""
echo "📱 Test notification:"
echo "curl -d 'Hello from the cloud!' http://$DROPLET_IP:8080/test"
