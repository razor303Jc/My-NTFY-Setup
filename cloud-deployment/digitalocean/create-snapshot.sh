#!/bin/bash

# Create snapshot of NTFY server droplet
set -e

DROPLET_ID="508876515"
SNAPSHOT_NAME="ntfy-server-configured-$(date +%Y%m%d-%H%M%S)"

echo "📸 Creating snapshot of NTFY server droplet"
echo "==========================================="
echo "Droplet ID: $DROPLET_ID"
echo "Snapshot Name: $SNAPSHOT_NAME"
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

# Check if droplet exists
print_status "Checking droplet status..."
DROPLET_INFO=$(doctl compute droplet get $DROPLET_ID --format ID,Name,Status,PublicIPv4 2>/dev/null || true)

if [ -z "$DROPLET_INFO" ]; then
    print_error "Droplet $DROPLET_ID not found"
    exit 1
fi

echo "Droplet Info:"
echo "$DROPLET_INFO"
echo ""

# Get droplet status
DROPLET_STATUS=$(doctl compute droplet get $DROPLET_ID --format Status --no-header 2>/dev/null || echo "unknown")

if [ "$DROPLET_STATUS" != "active" ]; then
    print_warning "Droplet is not active (Status: $DROPLET_STATUS)"
    echo "Do you want to continue creating the snapshot? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_status "Snapshot creation cancelled"
        exit 0
    fi
fi

# Power off droplet for consistent snapshot (optional but recommended)
print_warning "For best snapshot consistency, the droplet should be powered off"
echo "Options:"
echo "1. Power off droplet, create snapshot, then power back on (recommended)"
echo "2. Create snapshot while droplet is running (faster but less consistent)"
echo "3. Cancel"
echo ""
read -p "Choose option (1, 2, or 3): " choice

case $choice in
    1)
        print_status "Powering off droplet..."
        doctl compute droplet-action power-off $DROPLET_ID --wait
        POWERED_OFF=true
        ;;
    2)
        print_status "Creating snapshot while droplet is running..."
        POWERED_OFF=false
        ;;
    3)
        print_status "Snapshot creation cancelled"
        exit 0
        ;;
    *)
        print_error "Invalid choice. Exiting."
        exit 1
        ;;
esac

# Create snapshot
print_status "Creating snapshot: $SNAPSHOT_NAME"
echo "This may take several minutes..."

SNAPSHOT_ACTION=$(doctl compute droplet-action snapshot $DROPLET_ID --snapshot-name "$SNAPSHOT_NAME" --wait)

if [ $? -eq 0 ]; then
    print_status "✅ Snapshot created successfully!"
    
    # Get snapshot info
    print_status "Retrieving snapshot information..."
    sleep 5  # Wait a moment for snapshot to appear in list
    
    SNAPSHOT_INFO=$(doctl compute image list --public=false --format ID,Name,Type,Status | grep "$SNAPSHOT_NAME" || true)
    
    if [ -n "$SNAPSHOT_INFO" ]; then
        SNAPSHOT_ID=$(echo "$SNAPSHOT_INFO" | awk '{print $1}')
        echo ""
        echo "Snapshot Details:"
        echo "$SNAPSHOT_INFO"
        echo ""
        
        # Save snapshot info
        cat > snapshot-info.txt << EOF
Snapshot ID: $SNAPSHOT_ID
Snapshot Name: $SNAPSHOT_NAME
Source Droplet ID: $DROPLET_ID
Created: $(date)
Status: Ready for deployment
EOF
        
        print_status "Snapshot information saved to snapshot-info.txt"
    else
        print_warning "Snapshot created but details not immediately available"
        print_status "You can check snapshot status with: doctl compute image list --public=false"
    fi
    
else
    print_error "Failed to create snapshot"
    exit 1
fi

# Power droplet back on if we powered it off
if [ "$POWERED_OFF" = true ]; then
    print_status "Powering droplet back on..."
    doctl compute droplet-action power-on $DROPLET_ID --wait
    print_status "✅ Droplet powered back on"
fi

echo ""
echo "🎉 Snapshot creation complete!"
echo "=============================="
echo "Snapshot Name: $SNAPSHOT_NAME"
if [ -n "$SNAPSHOT_ID" ]; then
    echo "Snapshot ID: $SNAPSHOT_ID"
fi
echo ""
echo "Next steps:"
echo "1. Use this snapshot to deploy new droplets with: ./deploy-from-snapshot.sh"
echo "2. The snapshot includes all your NTFY configuration and setup"
echo "3. You can now destroy the original droplet if needed"
echo ""
echo "Snapshot management:"
echo "• List snapshots: doctl compute image list --public=false"
echo "• Delete snapshot: doctl compute image delete SNAPSHOT_ID"
