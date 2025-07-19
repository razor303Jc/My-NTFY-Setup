#!/bin/bash

# DigitalOcean NTFY Deployment Script
# This script creates a DigitalOcean droplet and deploys NTFY

set -e

# Configuration
DROPLET_NAME="ntfy-server"
DROPLET_SIZE="s-1vcpu-1gb"  # Basic droplet - upgrade as needed
DROPLET_IMAGE="ubuntu-24-04-x64"
DROPLET_REGION="lon1"  # Change to your preferred region
SSH_KEY_NAME="Sandbox-2"  # Will be set by user

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

select_reserved_ip() {
    print_status "Checking for available Reserved IPs..."
    
    # List all reserved IPs
    RESERVED_IPS=$(doctl compute reserved-ip list --format IP,Region,DropletID --no-header)
    
    if [ -z "$RESERVED_IPS" ]; then
        print_warning "No Reserved IPs found. Creating droplet without Reserved IP."
        RESERVED_IP=""
        return
    fi
    
    echo ""
    print_status "Available Reserved IPs:"
    echo "IP Address       Region    Assigned To"
    echo "----------------------------------------"
    echo "$RESERVED_IPS"
    echo ""
    
    read -p "Enter Reserved IP address to assign (or press Enter to skip): " RESERVED_IP_INPUT
    
    if [ -z "$RESERVED_IP_INPUT" ]; then
        print_status "No Reserved IP selected. Creating droplet with standard IP."
        RESERVED_IP=""
        return
    fi
    
    # Validate the Reserved IP exists and get its region
    RESERVED_IP_INFO=$(echo "$RESERVED_IPS" | grep "^$RESERVED_IP_INPUT")
    if [ -z "$RESERVED_IP_INFO" ]; then
        print_error "Reserved IP not found: $RESERVED_IP_INPUT"
        exit 1
    fi
    
    # Extract region from Reserved IP info
    RESERVED_IP_REGION=$(echo "$RESERVED_IP_INFO" | awk '{print $2}')
    RESERVED_IP_DROPLET=$(echo "$RESERVED_IP_INFO" | awk '{print $3}')
    
    # Check if already assigned
    if [ "$RESERVED_IP_DROPLET" != "-" ]; then
        print_error "Reserved IP $RESERVED_IP_INPUT is already assigned to droplet: $RESERVED_IP_DROPLET"
        exit 1
    fi
    
    # Update droplet region to match Reserved IP region
    if [ "$RESERVED_IP_REGION" != "$DROPLET_REGION" ]; then
        print_warning "Updating droplet region from $DROPLET_REGION to $RESERVED_IP_REGION to match Reserved IP"
        DROPLET_REGION="$RESERVED_IP_REGION"
    fi
    
    RESERVED_IP="$RESERVED_IP_INPUT"
    print_status "Using Reserved IP: $RESERVED_IP in region: $RESERVED_IP_REGION"
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
    
    # Assign Reserved IP if specified
    if [ -n "$RESERVED_IP" ]; then
        print_status "Assigning Reserved IP $RESERVED_IP to droplet..."
        doctl compute reserved-ip assign "$RESERVED_IP" "$DROPLET_ID"
        if [ $? -eq 0 ]; then
            print_status "Reserved IP assigned successfully!"
            DROPLET_IP="$RESERVED_IP"
        else
            print_error "Failed to assign Reserved IP. Using droplet's public IP instead."
            DROPLET_IP=$(doctl compute droplet get "$DROPLET_ID" --format PublicIPv4 --no-header)
        fi
    else
        # Get droplet IP
        DROPLET_IP=$(doctl compute droplet get "$DROPLET_ID" --format PublicIPv4 --no-header)
    fi
    
    print_status "Droplet is ready! IP: $DROPLET_IP"
    
    # Save droplet info
    cat > droplet-info.txt << EOF
Droplet ID: $DROPLET_ID
Droplet Name: $DROPLET_NAME
IP Address: $DROPLET_IP
Reserved IP: ${RESERVED_IP:-"None"}
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

# Copy SSH keys to ntfy user for deployment access
mkdir -p /home/ntfy/.ssh
cp /root/.ssh/authorized_keys /home/ntfy/.ssh/
chown -R ntfy:ntfy /home/ntfy/.ssh
chmod 700 /home/ntfy/.ssh
chmod 600 /home/ntfy/.ssh/authorized_keys

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
    
    # Parse command line arguments
    RESERVED_IP=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --reserved-ip)
                RESERVED_IP="$2"
                shift 2
                ;;
            --region)
                DROPLET_REGION="$2"
                shift 2
                ;;
            --with-ssl)
                WITH_SSL=true
                shift
                ;;
            *)
                # Unknown option, keep for backward compatibility
                break
                ;;
        esac
    done
    
    check_requirements
    select_ssh_key
    
    # Skip Reserved IP selection if one was provided via command line
    if [ -z "$RESERVED_IP" ]; then
        select_reserved_ip
    else
        print_status "Using provided Reserved IP: $RESERVED_IP"
    fi
    
    create_droplet
    setup_server
    deploy_ntfy
    
    if [ "$WITH_SSL" = true ] || [ "$1" = "--with-ssl" ]; then
        setup_ssl
    else
        print_warning "SSL not configured. Run with --with-ssl to set up SSL certificates"
    fi
    
    show_info
}

# Run main function
main "$@"
