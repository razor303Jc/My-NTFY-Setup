#!/bin/bash

# Monitor and continue NTFY deployment
DROPLET_IP="161.35.52.31"

echo "🔄 Monitoring droplet readiness..."
echo "Droplet IP: $DROPLET_IP"
echo ""

check_apt_lock() {
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$DROPLET_IP "ps aux | grep -E '(apt|dpkg)' | grep -v grep"
}

wait_for_apt() {
    echo "⏳ Waiting for automatic updates to complete..."
    while true; do
        if ! check_apt_lock > /dev/null 2>&1; then
            echo "✅ System is ready - no apt processes running"
            break
        else
            echo "⏱️  Still waiting... apt processes detected:"
            check_apt_lock | grep -E "(apt|dpkg)" | head -3
            sleep 30
        fi
    done
}

echo "🔍 Checking system status..."
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$DROPLET_IP "echo 'SSH connection successful'" 2>/dev/null; then
    echo "✅ SSH connection working"
    
    wait_for_apt
    
    echo ""
    echo "🚀 System is ready! Continuing deployment..."
    echo "Run: ./deploy.sh --continue"
    
else
    echo "❌ SSH connection failed. Waiting longer..."
    echo "Run this script again in a few minutes."
fi
