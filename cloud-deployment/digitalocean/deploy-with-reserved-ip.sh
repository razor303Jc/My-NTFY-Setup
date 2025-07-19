#!/bin/bash

# Script to deploy NTFY with existing Reserved IP
# This script will create a new droplet and assign your Reserved IP

set -e

RESERVED_IP="209.38.168.49"
DOMAIN="ntfy.razor303.co.uk"

echo "🚀 NTFY Deployment with Reserved IP"
echo "===================================="
echo "Reserved IP: $RESERVED_IP"
echo "Domain: $DOMAIN"
echo ""

# Check if the Reserved IP exists and get its details
echo "🔍 Checking Reserved IP status..."
RESERVED_IP_INFO=$(doctl compute reserved-ip list --format IP,Region,DropletID --no-header | grep "^$RESERVED_IP")

if [ -z "$RESERVED_IP_INFO" ]; then
    echo "❌ Reserved IP $RESERVED_IP not found in your account"
    echo "Please check your DigitalOcean dashboard or create the Reserved IP first."
    exit 1
fi

REGION=$(echo "$RESERVED_IP_INFO" | awk '{print $2}')
CURRENT_DROPLET=$(echo "$RESERVED_IP_INFO" | awk '{print $3}')

echo "✅ Reserved IP found in region: $REGION"

if [ "$CURRENT_DROPLET" != "-" ]; then
    echo "⚠️  Reserved IP is currently assigned to droplet: $CURRENT_DROPLET"
    echo ""
    echo "Options:"
    echo "1. Unassign from current droplet and deploy new one"
    echo "2. Exit and manually manage the assignment"
    echo ""
    read -p "Choose option (1 or 2): " choice
    
    case $choice in
        1)
            echo "🔄 Unassigning Reserved IP from current droplet..."
            doctl compute reserved-ip unassign "$RESERVED_IP"
            if [ $? -eq 0 ]; then
                echo "✅ Reserved IP unassigned successfully"
            else
                echo "❌ Failed to unassign Reserved IP"
                exit 1
            fi
            ;;
        2)
            echo "👋 Exiting. Please manually manage your Reserved IP assignment."
            exit 0
            ;;
        *)
            echo "❌ Invalid choice. Exiting."
            exit 1
            ;;
    esac
fi

echo ""
echo "🚀 Starting deployment with Reserved IP..."
echo "Region will be set to: $REGION"
echo ""

# Update the deploy.sh script to use this Reserved IP and region
export FORCE_RESERVED_IP="$RESERVED_IP"
export FORCE_REGION="$REGION"

# Run the deployment script with modifications
./deploy.sh --reserved-ip "$RESERVED_IP" --region "$REGION"

echo ""
echo "🎉 Deployment complete!"
echo "Reserved IP: $RESERVED_IP"
echo "Domain: $DOMAIN"
echo ""
echo "Next steps:"
echo "1. Wait 2-3 minutes for the droplet to fully boot"
echo "2. Check DNS: ./check-dns.sh"
echo "3. Deploy SSL: ./setup-ssl.sh"
