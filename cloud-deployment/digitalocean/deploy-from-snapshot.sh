#!/bin/bash

# Deploy NTFY from snapshot with Reserved IP
set -e

RESERVED_IP="209.38.168.49"
DOMAIN="ntfy.razor303.co.uk"

echo "🚀 Deploy NTFY from Snapshot with Reserved IP"
echo "============================================="
echo "Reserved IP: $RESERVED_IP"
echo "Domain: $DOMAIN"
echo ""

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

# Check if snapshot info exists
if [ ! -f "snapshot-info.txt" ]; then
    print_error "snapshot-info.txt not found"
    echo "Please create a snapshot first with: ./create-snapshot.sh"
    exit 1
fi

# Read snapshot info
SNAPSHOT_ID=$(grep "Snapshot ID:" snapshot-info.txt | cut -d' ' -f3)
SNAPSHOT_NAME=$(grep "Snapshot Name:" snapshot-info.txt | cut -d' ' -f3-)

if [ -z "$SNAPSHOT_ID" ]; then
    print_error "Could not read Snapshot ID from snapshot-info.txt"
    exit 1
fi

print_status "Using snapshot: $SNAPSHOT_NAME ($SNAPSHOT_ID)"

# Check if Reserved IP is available
print_status "Checking Reserved IP status..."
RESERVED_IP_INFO=$(doctl compute reserved-ip list --format IP,Region,DropletID | grep "^$RESERVED_IP" || true)

if [ -z "$RESERVED_IP_INFO" ]; then
    print_error "Reserved IP $RESERVED_IP not found in your account"
    exit 1
fi

REGION=$(echo "$RESERVED_IP_INFO" | awk '{print $2}')
CURRENT_DROPLET=$(echo "$RESERVED_IP_INFO" | awk '{print $3}')

print_status "Reserved IP region: $REGION"

if [ "$CURRENT_DROPLET" != "-" ] && [ -n "$CURRENT_DROPLET" ]; then
    print_warning "Reserved IP is currently assigned to droplet: $CURRENT_DROPLET"
    echo "Do you want to:"
    echo "1. Create new droplet anyway (you'll need to manually reassign the IP)"
    echo "2. Destroy current droplet and create new one"
    echo "3. Exit"
    echo ""
    read -p "Choose option (1, 2, or 3): " choice
    
    case $choice in
        1)
            print_status "Continuing with new droplet creation..."
            ;;
        2)
            print_warning "Destroying current droplet: $CURRENT_DROPLET"
            doctl compute droplet delete $CURRENT_DROPLET --force
            print_status "Waiting for droplet destruction to complete..."
            sleep 10
            ;;
        3)
            print_status "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
fi

# Get SSH key
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

# Create new droplet from snapshot
DROPLET_NAME="ntfy-server-new-$(date +%Y%m%d-%H%M%S)"
DROPLET_SIZE="s-1vcpu-1gb"

print_status "Creating droplet from snapshot..."
print_status "Droplet name: $DROPLET_NAME"
print_status "Region: $REGION"
print_status "Size: $DROPLET_SIZE"

DROPLET_ID=$(doctl compute droplet create "$DROPLET_NAME" \
    --size "$DROPLET_SIZE" \
    --image "$SNAPSHOT_ID" \
    --region "$REGION" \
    --ssh-keys "$SSH_KEY_NAME" \
    --enable-monitoring \
    --enable-private-networking \
    --format ID \
    --no-header)

if [ -z "$DROPLET_ID" ]; then
    print_error "Failed to create droplet from snapshot"
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
TEMP_IP=$(doctl compute droplet get "$DROPLET_ID" --format PublicIPv4 --no-header)
print_status "Droplet is ready with temporary IP: $TEMP_IP"

# Now assign the Reserved IP manually (since API assignment isn't working)
print_status "📋 Manual Reserved IP Assignment Required"
echo ""
echo "Please assign the Reserved IP manually:"
echo "1. Go to DigitalOcean Dashboard: https://cloud.digitalocean.com"
echo "2. Navigate to: Networking → Reserved IPs"
echo "3. Find Reserved IP: $RESERVED_IP"
echo "4. Click 'Assign' and select droplet: $DROPLET_NAME"
echo "5. Confirm the assignment"
echo ""
echo "Press Enter when you have completed the Reserved IP assignment..."
read -r

# Update droplet info
cat > droplet-info.txt << EOF
Droplet ID: $DROPLET_ID
Droplet Name: $DROPLET_NAME
IP Address: $RESERVED_IP
Reserved IP: $RESERVED_IP
Temporary IP: $TEMP_IP
Size: $DROPLET_SIZE
Region: $REGION
SSH Key: $SSH_KEY_NAME
Created from Snapshot: $SNAPSHOT_NAME ($SNAPSHOT_ID)
Created: $(date)
EOF

print_status "Droplet information saved to droplet-info.txt"

# Test SSH connectivity to Reserved IP
print_status "Testing SSH connectivity to Reserved IP..."
echo "Trying to connect to $RESERVED_IP..."

if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$RESERVED_IP 'echo "SSH connection successful"' 2>/dev/null; then
    print_status "✅ SSH connection to Reserved IP successful!"
    FINAL_IP="$RESERVED_IP"
else
    print_warning "SSH to Reserved IP failed, trying temporary IP..."
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$TEMP_IP 'echo "SSH connection successful"' 2>/dev/null; then
        print_status "✅ SSH connection to temporary IP successful!"
        print_warning "Reserved IP assignment may not be complete yet. Using temporary IP for now."
        FINAL_IP="$TEMP_IP"
    else
        print_error "SSH connection failed to both IPs. Please check network connectivity."
        exit 1
    fi
fi

# Check NTFY service status
print_status "Checking NTFY service status..."
NTFY_STATUS=$(ssh -o StrictHostKeyChecking=no ntfy@$FINAL_IP 'cd /opt/ntfy && docker-compose ps' 2>/dev/null || echo "Service check failed")

echo "NTFY Service Status:"
echo "$NTFY_STATUS"

# Test NTFY endpoint
print_status "Testing NTFY endpoint..."
if curl -s -f "http://$FINAL_IP:8080/v1/health" > /dev/null 2>&1; then
    print_status "✅ NTFY service is responding!"
else
    print_warning "NTFY service not responding yet. It may still be starting up."
    print_status "You can check status with: ssh ntfy@$FINAL_IP 'cd /opt/ntfy && docker-compose logs -f'"
fi

echo ""
echo "🎉 Deployment from snapshot complete!"
echo "===================================="
echo "New Droplet ID: $DROPLET_ID"
echo "Droplet Name: $DROPLET_NAME"
echo "Reserved IP: $RESERVED_IP"
echo "Temporary IP: $TEMP_IP"
echo "Final IP: $FINAL_IP"
echo ""
echo "URLs:"
echo "• HTTP: http://$FINAL_IP:8080"
echo "• Domain: http://$DOMAIN:8080 (once DNS propagates)"
echo ""
echo "Next steps:"
echo "1. Verify Reserved IP assignment completed"
echo "2. Check DNS: ./check-dns.sh"
echo "3. Deploy SSL: ./setup-ssl.sh"
echo "4. Clean up old droplet if needed"
echo ""
echo "Management commands:"
echo "• SSH: ssh ntfy@$FINAL_IP"
echo "• Logs: ssh ntfy@$FINAL_IP 'cd /opt/ntfy && docker-compose logs -f'"
echo "• Restart: ssh ntfy@$FINAL_IP 'cd /opt/ntfy && docker-compose restart'"
