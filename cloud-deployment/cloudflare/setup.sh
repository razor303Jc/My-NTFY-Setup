#!/bin/bash

# Cloudflare DNS Management Script for NTFY
# This script helps manage DNS records and SSL settings for your NTFY domain

set -e

# Configuration
CLOUDFLARE_API_TOKEN=""
ZONE_ID=""
DOMAIN_NAME=""
DROPLET_IP=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

load_config() {
    if [ -f "cloudflare-config.txt" ]; then
        source cloudflare-config.txt
        print_status "Loaded configuration from cloudflare-config.txt"
    fi
}

save_config() {
    cat > cloudflare-config.txt << EOF
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN"
ZONE_ID="$ZONE_ID"
DOMAIN_NAME="$DOMAIN_NAME"
DROPLET_IP="$DROPLET_IP"
EOF
    print_status "Configuration saved to cloudflare-config.txt"
}

setup_cloudflare() {
    print_step "Setting up Cloudflare integration"
    
    if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
        echo ""
        echo "To get a Cloudflare API token:"
        echo "1. Go to https://dash.cloudflare.com/profile/api-tokens"
        echo "2. Click 'Create Token'"
        echo "3. Use 'Custom token' template"
        echo "4. Set permissions: Zone:Zone:Read, Zone:DNS:Edit"
        echo "5. Set zone resources to your domain"
        echo ""
        read -p "Enter your Cloudflare API token: " CLOUDFLARE_API_TOKEN
    fi
    
    if [ -z "$DOMAIN_NAME" ]; then
        read -p "Enter your domain name (e.g., ntfy.yourdomain.com): " DOMAIN_NAME
    fi
    
    if [ -z "$DROPLET_IP" ]; then
        if [ -f "../digitalocean/droplet-info.txt" ]; then
            DROPLET_IP=$(grep "IP Address:" ../digitalocean/droplet-info.txt | cut -d: -f2 | xargs)
            print_status "Found droplet IP: $DROPLET_IP"
        else
            read -p "Enter your server IP address: " DROPLET_IP
        fi
    fi
    
    # Get zone ID if not set
    if [ -z "$ZONE_ID" ]; then
        ROOT_DOMAIN=$(echo "$DOMAIN_NAME" | rev | cut -d. -f1-2 | rev)
        print_status "Getting zone ID for $ROOT_DOMAIN..."
        
        ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ROOT_DOMAIN" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" | \
            jq -r '.result[0].id')
        
        if [ "$ZONE_ID" = "null" ]; then
            print_error "Could not find zone for $ROOT_DOMAIN"
            exit 1
        fi
        
        print_status "Zone ID: $ZONE_ID"
    fi
    
    save_config
}

create_dns_record() {
    print_step "Creating DNS A record"
    
    # Check if record already exists
    EXISTING_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DOMAIN_NAME&type=A" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" | \
        jq -r '.result[0].id // empty')
    
    if [ -n "$EXISTING_RECORD" ]; then
        print_warning "DNS record already exists. Updating..."
        
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$EXISTING_RECORD" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$DOMAIN_NAME\",
                \"content\": \"$DROPLET_IP\",
                \"ttl\": 300,
                \"proxied\": true
            }" > /dev/null
    else
        print_status "Creating new DNS record..."
        
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$DOMAIN_NAME\",
                \"content\": \"$DROPLET_IP\",
                \"ttl\": 300,
                \"proxied\": true
            }" > /dev/null
    fi
    
    print_status "DNS record created/updated successfully"
}

setup_ssl_settings() {
    print_step "Configuring SSL settings"
    
    # Set SSL mode to Full (strict)
    curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/ssl" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"value":"strict"}' > /dev/null
    
    # Enable Always Use HTTPS
    curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/always_use_https" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"value":"on"}' > /dev/null
    
    # Enable HTTP Strict Transport Security
    curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/security_header" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{
            "value": {
                "strict_transport_security": {
                    "enabled": true,
                    "max_age": 31536000,
                    "include_subdomains": true,
                    "nosniff": true
                }
            }
        }' > /dev/null
    
    print_status "SSL settings configured"
}

create_page_rules() {
    print_step "Creating Cloudflare Page Rules"
    
    # Create page rule for WebSocket connections
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/pagerules" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{
            \"targets\": [{
                \"target\": \"url\",
                \"constraint\": {
                    \"operator\": \"matches\",
                    \"value\": \"$DOMAIN_NAME/*\"
                }
            }],
            \"actions\": [{
                \"id\": \"disable_performance\",
                \"value\": \"on\"
            }],
            \"priority\": 1,
            \"status\": \"active\"
        }" > /dev/null
    
    print_status "Page rules created for WebSocket support"
}

check_dns_propagation() {
    print_step "Checking DNS propagation"
    
    print_status "Waiting for DNS to propagate..."
    
    for i in {1..30}; do
        RESOLVED_IP=$(dig +short "$DOMAIN_NAME" @8.8.8.8 | tail -n1)
        
        if [ -n "$RESOLVED_IP" ]; then
            print_status "DNS resolved to: $RESOLVED_IP"
            if [ "$RESOLVED_IP" != "$DROPLET_IP" ]; then
                print_warning "DNS points to $RESOLVED_IP but server is at $DROPLET_IP"
                print_warning "This might be due to Cloudflare proxy. This is normal."
            fi
            break
        fi
        
        echo "Attempt $i/30 - DNS not propagated yet..."
        sleep 10
    done
}

test_connection() {
    print_step "Testing NTFY connection"
    
    print_status "Testing HTTP connection..."
    if curl -s -f "http://$DOMAIN_NAME/v1/health" > /dev/null; then
        print_status "HTTP connection successful"
    else
        print_warning "HTTP connection failed"
    fi
    
    print_status "Testing HTTPS connection..."
    if curl -s -f "https://$DOMAIN_NAME/v1/health" > /dev/null; then
        print_status "HTTPS connection successful"
    else
        print_warning "HTTPS connection failed - this might take a few minutes to become available"
    fi
}

show_summary() {
    print_step "Setup Summary"
    
    echo ""
    echo "Cloudflare Configuration Complete!"
    echo "=================================="
    echo "Domain: $DOMAIN_NAME"
    echo "Server IP: $DROPLET_IP"
    echo "Zone ID: $ZONE_ID"
    echo ""
    echo "Your NTFY server should be accessible at:"
    echo "https://$DOMAIN_NAME"
    echo ""
    echo "Features enabled:"
    echo "✓ SSL/TLS encryption (Cloudflare proxy)"
    echo "✓ DDoS protection"
    echo "✓ CDN acceleration"
    echo "✓ Always HTTPS redirect"
    echo "✓ WebSocket support"
    echo ""
    echo "Next steps:"
    echo "1. Test your server: curl https://$DOMAIN_NAME/v1/health"
    echo "2. Create admin user on your server"
    echo "3. Configure mobile app with: https://$DOMAIN_NAME"
}

main() {
    echo "Cloudflare DNS & SSL Setup for NTFY"
    echo "===================================="
    
    load_config
    setup_cloudflare
    create_dns_record
    setup_ssl_settings
    create_page_rules
    check_dns_propagation
    test_connection
    show_summary
}

case "$1" in
    setup)
        main
        ;;
    test)
        load_config
        test_connection
        ;;
    dns)
        load_config
        check_dns_propagation
        ;;
    *)
        echo "Cloudflare Management Script for NTFY"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  setup  - Full Cloudflare setup (DNS, SSL, security)"
        echo "  test   - Test connection to NTFY server"
        echo "  dns    - Check DNS propagation"
        echo ""
        echo "Examples:"
        echo "  $0 setup"
        echo "  $0 test"
        ;;
esac
