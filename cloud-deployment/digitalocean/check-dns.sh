#!/bin/bash

# DNS Check Script for NTFY SSL Setup
# This script verifies that your domain is properly configured before SSL setup

DOMAIN="ntfy.razor303.co.uk"
EXPECTED_IP="209.38.168.49"

echo "🔍 Checking DNS configuration for $DOMAIN..."
echo "Expected IP: $EXPECTED_IP"
echo ""

# Check if dig is available
if ! command -v dig &> /dev/null; then
    echo "❌ 'dig' command not found. Installing dnsutils..."
    sudo apt-get update && sudo apt-get install -y dnsutils
fi

echo "⏳ Checking DNS resolution..."
RESOLVED_IP=$(dig +short $DOMAIN)

if [ -z "$RESOLVED_IP" ]; then
    echo "❌ Domain $DOMAIN does not resolve to any IP address"
    echo ""
    echo "📋 To fix this, add an A record to your DNS:"
    echo "   Domain: $DOMAIN"
    echo "   Type: A"
    echo "   Value: $EXPECTED_IP"
    echo "   TTL: 300 (5 minutes)"
    echo ""
    echo "🕐 DNS changes can take 5-15 minutes to propagate"
    exit 1
fi

if [ "$RESOLVED_IP" = "$EXPECTED_IP" ]; then
    echo "✅ DNS correctly configured!"
    echo "   $DOMAIN → $RESOLVED_IP"
    echo ""
    echo "🔒 You can now run SSL setup:"
    echo "   ./setup-ssl.sh"
    echo ""
    echo "📝 Note: Make sure your domain is accessible via HTTP first:"
    echo "   curl -I http://$DOMAIN"
else
    echo "❌ DNS misconfigured!"
    echo "   $DOMAIN → $RESOLVED_IP (Expected: $EXPECTED_IP)"
    echo ""
    echo "📋 Please update your DNS A record:"
    echo "   Current: $DOMAIN → $RESOLVED_IP"
    echo "   Should be: $DOMAIN → $EXPECTED_IP"
fi

echo ""
echo "🔄 Re-run this script after making DNS changes:"
echo "   ./check-dns.sh"
