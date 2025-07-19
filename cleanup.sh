#!/bin/bash

# NTFY Project Cleanup Script
# Removes temporary files, unused Docker resources, and old logs

set -e

echo "🧹 Starting NTFY Project Cleanup..."
echo "=================================="

# Function to print cleanup actions
cleanup_action() {
    echo "  ✓ $1"
}

# 1. Clean up automation logs (keep recent entries, truncate old ones)
if [ -f "automation.log" ]; then
    if [ $(wc -l < automation.log) -gt 100 ]; then
        echo "📋 Cleaning automation logs..."
        tail -50 automation.log > automation.log.tmp
        mv automation.log.tmp automation.log
        cleanup_action "Trimmed automation.log to last 50 entries"
    else
        cleanup_action "Automation log is already clean ($(wc -l < automation.log) lines)"
    fi
fi

# 2. Clean up Docker resources
echo "🐳 Cleaning Docker resources..."

# Remove dangling volumes (not used by any container)
DANGLING_VOLUMES=$(docker volume ls -f dangling=true -q)
if [ ! -z "$DANGLING_VOLUMES" ]; then
    docker volume rm $DANGLING_VOLUMES
    cleanup_action "Removed $(echo $DANGLING_VOLUMES | wc -w) dangling Docker volumes"
else
    cleanup_action "No dangling volumes to remove"
fi

# Clean up build cache
BUILD_CACHE_SIZE=$(docker system df --format "table {{.BuildCache}}" | tail -1)
if [ "$BUILD_CACHE_SIZE" != "0B" ]; then
    docker builder prune -f
    cleanup_action "Cleared Docker build cache ($BUILD_CACHE_SIZE)"
else
    cleanup_action "Docker build cache already empty"
fi

# 3. Remove any temporary files
echo "🗑️  Removing temporary files..."
find . -name "*.tmp" -delete 2>/dev/null || true
find . -name "*.temp" -delete 2>/dev/null || true
find . -name "*~" -delete 2>/dev/null || true
find . -name ".DS_Store" -delete 2>/dev/null || true
find . -name "Thumbs.db" -delete 2>/dev/null || true
cleanup_action "Removed temporary and system files"

# 4. Clean up empty attachment cache (if any)
if [ -d "ntfy-cache/attachments" ]; then
    find ntfy-cache/attachments -type f -size 0 -delete 2>/dev/null || true
    cleanup_action "Cleaned empty attachment files"
fi

# 5. Check if check-environment.sh is still needed
if [ -f "check-environment.sh" ]; then
    echo "❓ Found check-environment.sh script"
    echo "   This was used for initial setup verification."
    echo "   Since setup is complete, do you want to keep it? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Nn]$ ]]; then
        rm check-environment.sh
        cleanup_action "Removed check-environment.sh (no longer needed)"
    else
        cleanup_action "Kept check-environment.sh (user choice)"
    fi
fi

# 6. Show final disk usage
echo ""
echo "📊 Final Status:"
echo "=================="
echo "Project size:"
du -sh . 2>/dev/null | cut -f1
echo ""
echo "Docker usage after cleanup:"
docker system df

echo ""
echo "✅ Cleanup completed successfully!"
echo ""
echo "📁 Kept files:"
echo "  • Core configuration (ntfy-config/)"
echo "  • User data (ntfy-data/)"
echo "  • Management scripts (*.sh)"
echo "  • Message templates (message-templates.json)"
echo "  • Documentation (README.md, SETUP_COMPLETE.md)"
echo "  • Cloud deployment configs (cloud-deployment/)"
echo "  • Last 50 automation log entries"
