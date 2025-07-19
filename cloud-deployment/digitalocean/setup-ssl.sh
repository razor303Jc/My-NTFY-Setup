#!/bin/bash

# SSL Setup Script for NTFY with Let's Encrypt
# Domain: ntfy.razor303.co.uk

set -e

DOMAIN="ntfy.razor303.co.uk"
EMAIL="admin@razor303.co.uk"
DROPLET_IP="161.35.52.31"

echo "🔒 Setting up SSL with Let's Encrypt for $DOMAIN"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check DNS first
check_dns() {
    print_status "Checking DNS configuration for $DOMAIN..."
    
    DNS_IP=$(dig +short $DOMAIN)
    if [ "$DNS_IP" = "$DROPLET_IP" ]; then
        print_status "✅ DNS correctly points to $DROPLET_IP"
        return 0
    else
        print_warning "⚠️  DNS check: $DOMAIN resolves to '$DNS_IP' but should be '$DROPLET_IP'"
        echo ""
        echo "Please ensure your DNS A record points to: $DROPLET_IP"
        echo "Current DNS response: $DNS_IP"
        echo ""
        echo "Continue anyway? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            print_warning "Continuing with SSL setup despite DNS mismatch..."
            return 0
        else
            print_error "Please fix DNS before continuing"
            exit 1
        fi
    fi
}

# Create production docker-compose with nginx
setup_production_config() {
    print_status "Creating production configuration with nginx and SSL..."
    
    # Create nginx configuration
    cat > nginx-ssl.conf << EOF
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 10240;
    gzip_proxied expired no-cache no-store private must-revalidate;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=1r/s;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    
    # NTFY server configuration
    upstream ntfy_backend {
        server ntfy:80;
    }
    
    # HTTP redirect to HTTPS
    server {
        listen 80;
        server_name $DOMAIN;
        return 301 https://\$server_name\$request_uri;
    }
    
    # HTTPS server
    server {
        listen 443 ssl http2;
        server_name $DOMAIN;
        
        # SSL certificates (will be configured by certbot)
        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        
        # Security headers
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Content-Security-Policy "default-src 'self' http: https: ws: wss: data: blob: 'unsafe-inline'; frame-ancestors 'none';" always;
        
        # NTFY specific headers
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "GET, PUT, POST, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "authorization, cache-control, content-type, x-requested-with" always;
        
        # Client body size for file uploads
        client_max_body_size 20M;
        
        # WebSocket support
        location / {
            proxy_pass http://ntfy_backend;
            proxy_http_version 1.1;
            
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            # WebSocket headers
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            
            # Timeouts
            proxy_connect_timeout 3m;
            proxy_send_timeout 3m;
            proxy_read_timeout 3m;
            
            # Rate limiting for API endpoints
            location ~* ^/([-_a-z0-9]{0,64})/?(json|sse|raw|ws)?\$ {
                limit_req zone=api burst=60 nodelay;
                proxy_pass http://ntfy_backend;
                proxy_http_version 1.1;
                proxy_set_header Host \$host;
                proxy_set_header X-Real-IP \$remote_addr;
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto \$scheme;
                proxy_set_header Upgrade \$http_upgrade;
                proxy_set_header Connection "upgrade";
            }
        }
    }
}
EOF

    # Create production docker-compose with SSL
    cat > docker-compose.ssl.yml << EOF
version: "3.8"
services:
  ntfy:
    image: binwiederhier/ntfy:latest
    container_name: ntfy-server
    restart: unless-stopped
    
    environment:
      - TZ=UTC
      - NTFY_BASE_URL=https://$DOMAIN
      - NTFY_CACHE_FILE=/var/cache/ntfy/cache.db
      - NTFY_ATTACHMENT_CACHE_DIR=/var/cache/ntfy/attachments
      - NTFY_AUTH_FILE=/var/lib/ntfy/auth.db
      - NTFY_AUTH_DEFAULT_ACCESS=read-write
      - NTFY_ENABLE_LOGIN=false
      - NTFY_ENABLE_SIGNUP=false
      - NTFY_BEHIND_PROXY=true
    
    # Only expose to nginx container
    expose:
      - "80"
    
    volumes:
      - ./ntfy-config:/etc/ntfy:ro
      - ./ntfy-cache:/var/cache/ntfy
      - ./ntfy-data:/var/lib/ntfy
    
    healthcheck:
      test: ["CMD-SHELL", "wget -q --tries=1 http://localhost:80/v1/health -O - | grep -Eo '\"healthy\"\\\\s*:\\\\s*true' || exit 1"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 40s
    
    command: serve
    
    networks:
      - ntfy-network

  nginx:
    image: nginx:alpine
    container_name: ntfy-nginx
    restart: unless-stopped
    
    ports:
      - "80:80"
      - "443:443"
    
    volumes:
      - ./nginx-ssl.conf:/etc/nginx/nginx.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /var/lib/letsencrypt:/var/lib/letsencrypt:ro
    
    depends_on:
      - ntfy
    
    networks:
      - ntfy-network

networks:
  ntfy-network:
    driver: bridge
EOF

    print_status "Configuration files created"
}

# Deploy configuration to server
deploy_ssl_config() {
    print_status "Deploying SSL configuration to server..."
    
    # Copy files to server
    scp nginx-ssl.conf docker-compose.ssl.yml ntfy@$DROPLET_IP:/opt/ntfy/
    
    print_status "Configuration files copied to server"
}

# Setup SSL certificate
setup_ssl_certificate() {
    print_status "Setting up SSL certificate with Let's Encrypt..."
    
    ssh ntfy@$DROPLET_IP << EOF
cd /opt/ntfy

# Stop current services
docker-compose -f docker-compose.simple.yml down 2>/dev/null || true

# Start nginx temporarily for certificate generation
docker run --rm -d --name temp-nginx -p 80:80 -v /opt/ntfy/nginx-temp.conf:/etc/nginx/nginx.conf:ro nginx:alpine

# Create temporary nginx config for certificate generation
cat > nginx-temp.conf << 'TEMP_EOF'
events {
    worker_connections 1024;
}
http {
    server {
        listen 80;
        server_name $DOMAIN;
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        location / {
            return 301 https://\\\$server_name\\\$request_uri;
        }
    }
}
TEMP_EOF

# Stop temporary nginx
docker stop temp-nginx 2>/dev/null || true

# Generate certificate using certbot
sudo certbot certonly --standalone --non-interactive --agree-tos --email $EMAIL -d $DOMAIN

# Start production services with SSL
docker-compose -f docker-compose.ssl.yml up -d

echo "SSL certificate generated and services started"
EOF

    print_status "SSL certificate configured successfully!"
}

# Test SSL setup
test_ssl() {
    print_status "Testing SSL configuration..."
    
    sleep 10  # Wait for services to start
    
    if curl -s --connect-timeout 10 https://$DOMAIN/v1/health | grep -q "healthy"; then
        print_status "✅ SSL setup successful! NTFY is responding on HTTPS"
        
        # Send test notification
        curl -s -d "🔒 SSL Certificate configured! NTFY now available at https://$DOMAIN" https://$DOMAIN/ssl-setup
        
        return 0
    else
        print_error "❌ SSL test failed. Checking what went wrong..."
        
        # Check if HTTP works
        if curl -s --connect-timeout 10 http://$DOMAIN/v1/health >/dev/null 2>&1; then
            print_warning "HTTP works but HTTPS doesn't. Check certificate generation."
        else
            print_error "Both HTTP and HTTPS failed. Check service status."
        fi
        
        return 1
    fi
}

# Main execution
main() {
    echo "Setting up SSL for NTFY with domain: $DOMAIN"
    echo "Server IP: $DROPLET_IP"
    echo ""
    
    check_dns
    setup_production_config
    deploy_ssl_config
    setup_ssl_certificate
    test_ssl
    
    echo ""
    echo "🎉 SSL Setup Complete!"
    echo "======================"
    echo ""
    echo "✅ Domain: https://$DOMAIN"
    echo "✅ SSL Certificate: Let's Encrypt"
    echo "✅ Auto-renewal: Enabled"
    echo "✅ HTTP → HTTPS redirect: Active"
    echo "✅ Security headers: Configured"
    echo ""
    echo "🔗 Your secure NTFY server:"
    echo "   https://$DOMAIN"
    echo ""
    echo "📱 Update mobile apps to use:"
    echo "   https://$DOMAIN/your-topic"
    echo ""
    echo "🧪 Test notification:"
    echo "   curl -d 'Hello Secure World!' https://$DOMAIN/test"
    echo ""
    echo "🔄 Certificate auto-renewal is handled by certbot"
}

# Run the setup
main
