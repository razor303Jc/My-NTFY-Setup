#!/bin/bash

# Assign Reserved IP to Droplet using DigitalOcean API
set -e

RESERVED_IP="209.38.168.49"
DROPLET_ID="508876515"

echo "🔗 Assigning Reserved IP $RESERVED_IP to Droplet $DROPLET_ID"

# Get the API token from doctl config
API_TOKEN=$(grep 'access-token' ~/.config/doctl/config.yaml | cut -d' ' -f2)

if [ -z "$API_TOKEN" ]; then
    echo "❌ Could not get API token from doctl config"
    echo "Please ensure you're authenticated with: doctl auth init"
    echo "Or manually set API_TOKEN environment variable"
    exit 1
fi

# Assign the Reserved IP using the API
echo "📡 Making API call to assign Reserved IP..."

RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_TOKEN" \
    -d '{"type": "assign", "resource": '"$DROPLET_ID"'}' \
    "https://api.digitalocean.com/v2/reserved_ips/$RESERVED_IP/actions")

echo "API Response: $RESPONSE"

# Check if the assignment was successful
if echo "$RESPONSE" | grep -q '"status":"in-progress"'; then
    echo "✅ Reserved IP assignment initiated successfully!"
    echo "⏳ Waiting for assignment to complete..."
    
    # Wait a bit for the assignment to complete
    sleep 10
    
    # Check the final status
    DROPLET_INFO=$(doctl compute droplet get $DROPLET_ID --format ID,Name,PublicIPv4,Status,Region --no-header)
    echo "Updated Droplet Info: $DROPLET_INFO"
    
    # Update droplet-info.txt with the new IP
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
    
    echo "📝 Updated droplet-info.txt with Reserved IP"
    echo ""
    echo "🎉 Success! Your droplet now uses Reserved IP: $RESERVED_IP"
    echo ""
    echo "Next steps:"
    echo "1. Wait 2-3 minutes for network changes to propagate"
    echo "2. Check DNS: ./check-dns.sh" 
    echo "3. Test SSH: ssh root@$RESERVED_IP"
    echo "4. Continue setup: ./continue-deploy.sh"
    
else
    echo "❌ Failed to assign Reserved IP"
    echo "Response: $RESPONSE"
    echo ""
    echo "You can try to assign it manually in the DigitalOcean dashboard:"
    echo "1. Go to Networking > Reserved IPs"
    echo "2. Click on $RESERVED_IP"
    echo "3. Assign it to droplet 'ntfy-server' ($DROPLET_ID)"
fi
