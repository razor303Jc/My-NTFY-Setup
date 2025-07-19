#!/bin/bash

# DigitalOcean NTFY Deployment Script
# This script creates a DigitalOcean droplet and deploys NTFY

set -e

# Configuration
DROPLET_NAME="ntfy-server"
DROPLET_SIZE="s-1vcpu-1gb"  # Basic droplet - upgrade as needed
DROPLET_IMAGE="ubuntu-24-04-x64"
DROPLET_REGION="nyc1"  # Change to your preferred region
SSH_KEY_NAME=""  # Will be set by user

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    print_status "Checking requirements..."
    
    # Check if doctl is installed
    if ! command -v doctl &> /dev/null; then
        print_error "doctl (DigitalOcean CLI) is not installed"
        echo "Install it with: snap install doctl"
        echo "Or download from: https://github.com/digitalocean/doctl/releases"
        exit 1
    fi
    
    # Check if authenticated
    if ! doctl auth list &> /dev/null; then
        print_error "DigitalOcean CLI not authenticated"
        echo "Run: doctl auth init"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed"
        echo "Install it with: sudo apt install jq"
        exit 1
    fi
    
    print_status "All requirements met!"
}

select_ssh_key() {
    print_status "Available SSH keys:"
    doctl compute ssh-key list --format ID,Name
    
    echo ""
    read -p "Enter SSH key ID or name: " SSH_KEY_INPUT
    
    # Validate SSH key exists
    if ! doctl compute ssh-key get "$SSH_KEY_INPUT" &> /dev/null; then
        print_error "SSH key not found: $SSH_KEY_INPUT"
        exit 1
    fi
    
    SSH_KEY_NAME="$SSH_KEY_INPUT"
    print_status "Using SSH key: $SSH_KEY_NAME"
}

create_droplet() {
    print_status "Creating DigitalOcean droplet..."
    
    DROPLET_ID=$(doctl compute droplet create "$DROPLET_NAME" \
        --size "$DROPLET_SIZE" \
        --image "$DROPLET_IMAGE" \
        --region "$DROPLET_REGION" \
        --ssh-keys "$SSH_KEY_NAME" \
        --enable-monitoring \
        --enable-private-networking \
        --format ID \
        --no-header)
    
    if [ -z "$DROPLET_ID" ]; then
        print_error "Failed to create droplet"
        exit 1
    fi
    
    print_status "Droplet created with ID: $DROPLET_ID"
    print_status "Waiting for droplet to be ready..."
    
    # Wait for droplet to be active
    while true; do
        STATUS=$(doctl compute droplet get "$DROPLET_ID" --format Status --no-header)
        if [ "$STATUS" = "active" ]; then
            break
        fi
        echo "Status: $STATUS - waiting..."
        sleep 10
    done
    
    # Get droplet IP
    DROPLET_IP=$(doctl compute droplet get "$DROPLET_ID" --format PublicIPv4 --no-header)
    print_status "Droplet is ready! IP: $DROPLET_IP"
    
    # Save droplet info
    cat > droplet-info.txt << EOF
Droplet ID: $DROPLET_ID
Droplet Name: $DROPLET_NAME
IP Address: $DROPLET_IP
Size: $DROPLET_SIZE
Region: $DROPLET_REGION
SSH Key: $SSH_KEY_NAME
Created: $(date)
EOF
    
    print_status "Droplet information saved to droplet-info.txt"
}

setup_server() {
    print_status "Setting up the server..."
    
    # Create setup script
    cat > setup-server.sh << 'EOF'
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
EOF

    # Wait for SSH to be ready
    print_status "Waiting for SSH to be ready..."
    sleep 30
    
    # Copy and run setup script
    scp -o StrictHostKeyChecking=no setup-server.sh root@$DROPLET_IP:/tmp/
    ssh -o StrictHostKeyChecking=no root@$DROPLET_IP 'bash /tmp/setup-server.sh'
    
    print_status "Server setup complete!"
}

deploy_ntfy() {
    print_status "Deploying NTFY..."
    
    # Copy deployment files
    scp -o StrictHostKeyChecking=no -r ../cloud-deployment/* ntfy@$DROPLET_IP:/opt/ntfy/
    
    # Deploy NTFY
    ssh -o StrictHostKeyChecking=no ntfy@$DROPLET_IP << 'EOF'
cd /opt/ntfy
mkdir -p ntfy-cache ntfy-data ssl

# Start NTFY
docker-compose -f docker-compose.production.yml up -d

echo "NTFY deployed!"
EOF

    print_status "NTFY deployment complete!"
}

setup_ssl() {
    print_status "Setting up SSL certificates..."
    print_warning "Make sure your domain is pointing to $DROPLET_IP"
    
    read -p "Enter your domain name: " DOMAIN_NAME
    
    # Update configuration files with actual domain
    ssh ntfy@$DROPLET_IP << "EOF"
cd /opt/ntfy
sed -i 's/your-domain.com/'$DOMAIN_NAME'/g' nginx.conf
sed -i 's/your-domain.com/'$DOMAIN_NAME'/g' ntfy-config/server.yml
sed -i 's/your-domain.com/'$DOMAIN_NAME'/g' docker-compose.production.yml
EOF

    # Setup SSL
    ssh root@$DROPLET_IP << "EOF"
certbot certonly --nginx -d $DOMAIN_NAME --non-interactive --agree-tos --email admin@$DOMAIN_NAME
cp /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem /opt/ntfy/ssl/
cp /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem /opt/ntfy/ssl/
chown -R ntfy:ntfy /opt/ntfy/ssl/

# Setup auto-renewal
echo "0 2 * * * certbot renew --quiet && cp /etc/letsencrypt/live/$DOMAIN_NAME/*.pem /opt/ntfy/ssl/ && docker-compose -f /opt/ntfy/docker-compose.production.yml restart nginx" | crontab -
EOF

    # Restart services
    ssh ntfy@$DROPLET_IP << 'EOF'
cd /opt/ntfy
docker-compose -f docker-compose.production.yml restart
EOF

    print_status "SSL setup complete!"
}

show_info() {
    print_status "Deployment Summary:"
    echo "Droplet IP: $DROPLET_IP"
    echo "NTFY URL: https://$DOMAIN_NAME (once DNS propagates)"
    echo ""
    echo "Next steps:"
    echo "1. Point your domain to IP: $DROPLET_IP"
    echo "2. Wait for DNS propagation"
    echo "3. Create admin user: ssh ntfy@$DROPLET_IP 'docker exec ntfy-server ntfy user add --role=admin admin'"
    echo "4. Access your NTFY server at: https://$DOMAIN_NAME"
    echo ""
    echo "Management commands:"
    echo "- SSH to server: ssh ntfy@$DROPLET_IP"
    echo "- View logs: ssh ntfy@$DROPLET_IP 'docker-compose -f /opt/ntfy/docker-compose.production.yml logs -f'"
    echo "- Restart services: ssh ntfy@$DROPLET_IP 'docker-compose -f /opt/ntfy/docker-compose.production.yml restart'"
}

main() {
    echo "DigitalOcean NTFY Deployment Script"
    echo "===================================="
    
    check_requirements
    select_ssh_key
    create_droplet
    setup_server
    deploy_ntfy
    
    if [ "$1" = "--with-ssl" ]; then
        setup_ssl
    else
        print_warning "SSL not configured. Run with --with-ssl to set up SSL certificates"
    fi
    
    show_info
}

# Run main function
main "$@"
