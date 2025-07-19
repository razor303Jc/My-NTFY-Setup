#!/bin/bash

# Environment Check Script for NTFY Cloud Deployment
# This script checks if all requirements are met for cloud deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}==== $1 ====${NC}"
}

print_check() {
    echo -n "Checking $1... "
}

print_ok() {
    echo -e "${GREEN}✓ OK${NC}"
}

print_fail() {
    echo -e "${RED}✗ FAILED${NC}"
    echo -e "${YELLOW}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING${NC}"
    echo -e "${YELLOW}$1${NC}"
}

check_local_setup() {
    print_header "Local NTFY Setup"
    
    print_check "Docker installation"
    if command -v docker &> /dev/null; then
        print_ok
    else
        print_fail "Docker is not installed. Please install Docker first."
        return 1
    fi
    
    print_check "Docker Compose installation"
    if command -v docker-compose &> /dev/null; then
        print_ok
    else
        print_fail "Docker Compose is not installed. Please install Docker Compose first."
        return 1
    fi
    
    print_check "Local NTFY server"
    if docker ps | grep -q ntfy-server; then
        print_ok
    else
        print_warning "Local NTFY server is not running. Run './ntfy-manager.sh start' to start it."
    fi
    
    print_check "Local server accessibility"
    if curl -s -f http://localhost:8080/v1/health > /dev/null 2>&1; then
        print_ok
    else
        print_warning "Local NTFY server is not accessible on port 8080."
    fi
}

check_digitalocean_requirements() {
    print_header "DigitalOcean Requirements"
    
    print_check "doctl (DigitalOcean CLI)"
    if command -v doctl &> /dev/null; then
        print_ok
    else
        print_fail "doctl is not installed. Install with: sudo snap install doctl"
        return 1
    fi
    
    print_check "DigitalOcean authentication"
    if doctl auth list &> /dev/null; then
        print_ok
    else
        print_fail "DigitalOcean CLI not authenticated. Run: doctl auth init"
        return 1
    fi
    
    print_check "SSH key availability"
    SSH_KEYS=$(doctl compute ssh-key list --format Name --no-header 2>/dev/null | wc -l)
    if [ "$SSH_KEYS" -gt 0 ]; then
        print_ok
        echo "   Found $SSH_KEYS SSH key(s)"
    else
        print_fail "No SSH keys found in DigitalOcean account. Add an SSH key first."
        return 1
    fi
    
    print_check "jq installation"
    if command -v jq &> /dev/null; then
        print_ok
    else
        print_fail "jq is not installed. Install with: sudo apt install jq"
        return 1
    fi
}

check_cloudflare_requirements() {
    print_header "Cloudflare Requirements"
    
    print_check "curl availability"
    if command -v curl &> /dev/null; then
        print_ok
    else
        print_fail "curl is not installed. Install with: sudo apt install curl"
        return 1
    fi
    
    print_check "dig (DNS tools)"
    if command -v dig &> /dev/null; then
        print_ok
    else
        print_fail "dig is not installed. Install with: sudo apt install dnsutils"
        return 1
    fi
    
    print_check "Cloudflare configuration"
    if [ -f "cloud-deployment/cloudflare/cloudflare-config.txt" ]; then
        print_ok
        echo "   Found existing Cloudflare configuration"
    else
        print_warning "No Cloudflare configuration found. Run './setup.sh setup' in cloudflare directory to configure."
    fi
}

show_deployment_readiness() {
    print_header "Deployment Readiness Summary"
    
    echo ""
    echo "Ready for deployment steps:"
    echo ""
    echo "1. Local Setup:"
    if docker ps | grep -q ntfy-server; then
        echo -e "   ${GREEN}✓${NC} Local NTFY server is running"
    else
        echo -e "   ${YELLOW}!${NC} Start local server: ./ntfy-manager.sh start"
    fi
    
    echo ""
    echo "2. DigitalOcean Deployment:"
    if command -v doctl &> /dev/null && doctl auth list &> /dev/null; then
        echo -e "   ${GREEN}✓${NC} Ready for DigitalOcean deployment"
        echo "   → Run: cd cloud-deployment/digitalocean && ./deploy.sh --with-ssl"
    else
        echo -e "   ${RED}✗${NC} Not ready for DigitalOcean deployment"
        echo "   → Install and authenticate doctl first"
    fi
    
    echo ""
    echo "3. Cloudflare Setup:"
    if command -v curl &> /dev/null && command -v dig &> /dev/null; then
        echo -e "   ${GREEN}✓${NC} Ready for Cloudflare setup"
        echo "   → Run: cd cloud-deployment/cloudflare && ./setup.sh setup"
    else
        echo -e "   ${RED}✗${NC} Not ready for Cloudflare setup"
        echo "   → Install required tools first"
    fi
    
    echo ""
    echo "Need help? Check README.md for detailed instructions."
}

show_next_steps() {
    print_header "Next Steps"
    
    echo ""
    echo "To deploy NTFY to the cloud:"
    echo ""
    echo "1. Test local setup:"
    echo "   ./ntfy-manager.sh start"
    echo "   ./ntfy-manager.sh test"
    echo ""
    echo "2. Deploy to DigitalOcean:"
    echo "   cd cloud-deployment/digitalocean"
    echo "   ./deploy.sh --with-ssl"
    echo ""
    echo "3. Configure Cloudflare:"
    echo "   cd cloud-deployment/cloudflare"
    echo "   ./setup.sh setup"
    echo ""
    echo "4. Test your cloud deployment:"
    echo "   curl https://your-domain.com/v1/health"
    echo ""
    echo "5. Create admin user:"
    echo "   ssh ntfy@your-server-ip 'docker exec ntfy-server ntfy user add --role=admin admin'"
    echo ""
}

main() {
    echo "NTFY Deployment Environment Check"
    echo "================================="
    echo ""
    
    LOCAL_OK=true
    DO_OK=true
    CF_OK=true
    
    if ! check_local_setup; then
        LOCAL_OK=false
    fi
    
    echo ""
    
    if ! check_digitalocean_requirements; then
        DO_OK=false
    fi
    
    echo ""
    
    if ! check_cloudflare_requirements; then
        CF_OK=false
    fi
    
    echo ""
    
    show_deployment_readiness
    
    if [ "$LOCAL_OK" = true ] && [ "$DO_OK" = true ] && [ "$CF_OK" = true ]; then
        echo ""
        echo -e "${GREEN}🎉 All requirements met! You're ready for cloud deployment.${NC}"
        show_next_steps
    else
        echo ""
        echo -e "${YELLOW}⚠ Some requirements are missing. Please install missing components first.${NC}"
    fi
}

main "$@"
