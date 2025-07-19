#!/bin/bash

# Fix NTFY deployment - handle SSH keys for ntfy user
# This script fixes the SSH access issue and completes deployment

set -e

DROPLET_IP="161.35.52.31"

echo "🔧 Fixing NTFY deployment..."
echo "Droplet IP: $DROPLET_IP"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fix SSH access for ntfy user
fix_ssh_access() {
    print_status "Setting up SSH access for ntfy user..."
    
    # Copy SSH keys to ntfy user and complete setup
    ssh -o StrictHostKeyChecking=no root@$DROPLET_IP << 'EOF'
# Copy SSH authorized keys to ntfy user
mkdir -p /home/ntfy/.ssh
cp /root/.ssh/authorized_keys /home/ntfy/.ssh/
chown -R ntfy:ntfy /home/ntfy/.ssh
chmod 700 /home/ntfy/.ssh
chmod 600 /home/ntfy/.ssh/authorized_keys

# Add ntfy to sudo group for deployment tasks
usermod -aG sudo ntfy

# Allow ntfy to use docker without sudo
usermod -aG docker ntfy

echo "SSH access configured for ntfy user"
EOF

    print_status "SSH access fixed for ntfy user"
}

# Deploy NTFY files and configuration
deploy_ntfy() {
    print_status "Deploying NTFY configuration..."
    
    # Copy deployment files to ntfy user
    print_status "Copying NTFY files to server..."
    scp -o StrictHostKeyChecking=no -r ../* ntfy@$DROPLET_IP:/opt/ntfy/
    
    # Deploy and start NTFY
    print_status "Starting NTFY services..."
    ssh -o StrictHostKeyChecking=no ntfy@$DROPLET_IP << 'EOF'
cd /opt/ntfy
mkdir -p ntfy-cache ntfy-data ssl

# Ensure we have the production config file
if [ ! -f docker-compose.production.yml ]; then
    echo "docker-compose.production.yml not found, using docker-compose.yml"
    cp docker-compose.yml docker-compose.production.yml
fi

# Start NTFY services
docker-compose -f docker-compose.production.yml up -d

echo "NTFY services started!"
EOF

    print_status "NTFY deployment complete!"
}

# Configure SSL and domain
configure_ssl() {
    print_status "Setting up SSL certificate..."
    
    echo ""
    echo "Enter your domain name (e.g., ntfy.yourdomain.com):"
    read -r DOMAIN
    
    if [ -z "$DOMAIN" ]; then
        print_error "Domain name is required for SSL setup"
        echo ""
        echo "🎉 Your NTFY server is ready at: http://$DROPLET_IP:8080"
        echo ""
        echo "To set up SSL later, run this script again with a domain"
        return 0
    fi
    
    print_status "Configuring SSL for domain: $DOMAIN"
    
    ssh -o StrictHostKeyChecking=no ntfy@$DROPLET_IP << EOF
# Check if nginx config exists
if [ -f /opt/ntfy/nginx.conf ]; then
    sudo cp /opt/ntfy/nginx.conf /etc/nginx/sites-available/ntfy
    sudo sed -i 's/your-domain.com/$DOMAIN/g' /etc/nginx/sites-available/ntfy
    sudo ln -sf /etc/nginx/sites-available/ntfy /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo nginx -t && sudo systemctl reload nginx
    
    # Get SSL certificate
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
    
    echo "SSL certificate configured for $DOMAIN"
else
    echo "Warning: nginx.conf not found in /opt/ntfy/"
    echo "You'll need to configure nginx manually"
fi
EOF
    
    if [ $? -eq 0 ]; then
        print_status "SSL setup complete!"
        echo ""
        echo "🎉 Your NTFY server is ready at: https://$DOMAIN"
    else
        echo ""
        echo "⚠️  SSL setup had issues, but NTFY is running at: http://$DROPLET_IP:8080"
    fi
}

# Test the deployment
test_deployment() {
    print_status "Testing NTFY deployment..."
    
    # Test basic connectivity
    if curl -s --connect-timeout 10 http://$DROPLET_IP:8080/v1/health > /dev/null; then
        print_status "✅ NTFY server is responding!"
        
        # Send a test notification
        RESPONSE=$(curl -s -d "🎉 NTFY cloud deployment successful!" http://$DROPLET_IP:8080/test-deployment)
        if [ $? -eq 0 ]; then
            print_status "✅ Test notification sent successfully!"
        fi
    else
        print_error "❌ NTFY server is not responding on port 8080"
        echo "Check the deployment logs with: ssh ntfy@$DROPLET_IP 'docker logs \$(docker ps -q)'"
    fi
}

# Main deployment process
main() {
    fix_ssh_access
    deploy_ntfy
    test_deployment
    
    echo ""
    echo "🎉 NTFY deployment completed!"
    echo ""
    echo "📋 What's been deployed:"
    echo "  • NTFY server running in Docker"
    echo "  • Health check endpoint: http://$DROPLET_IP:8080/v1/health"
    echo "  • Web interface: http://$DROPLET_IP:8080"
    echo "  • Firewall configured (ports 22, 80, 443 open)"
    echo "  • Docker and Docker Compose installed"
    echo ""
    echo "📱 Send a test notification:"
    echo "curl -d 'Hello from the cloud!' http://$DROPLET_IP:8080/test"
    echo ""
    
    # Ask about SSL setup
    echo "Would you like to set up SSL with a domain name? (y/n)"
    read -r setup_ssl
    if [[ "$setup_ssl" =~ ^[Yy]$ ]]; then
        configure_ssl
    else
        echo ""
        echo "📝 To set up SSL later:"
        echo "1. Point your domain's DNS to $DROPLET_IP"
        echo "2. Run this script again and choose SSL setup"
    fi
    
    echo ""
    echo "🚀 Your NTFY server is ready for use!"
}

# Run the deployment
main
