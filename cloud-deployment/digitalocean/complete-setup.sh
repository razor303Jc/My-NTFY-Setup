#!/bin/bash
set -e

echo "🔧 Completing server setup..."

# Create ntfy user if it doesn't exist
if ! id -u ntfy &>/dev/null; then
    useradd -m -s /bin/bash ntfy
    usermod -aG docker ntfy
    echo "✅ Created ntfy user"
else
    echo "✅ ntfy user already exists"
fi

# Create directories
mkdir -p /opt/ntfy
chown ntfy:ntfy /opt/ntfy

# Ensure Docker is running
systemctl enable docker
systemctl start docker

echo "✅ Server setup complete!"
