# NTFY Server Setup Guide

A complete setup guide for running NTFY (notification service) locally and in the cloud with DigitalOcean and Cloudflare.

## What is NTFY?

NTFY is a simple HTTP-based push notification service that allows you to:
- Send notifications to your phone via HTTP requests
- Subscribe to topics for organized notifications
- Use a web interface, mobile apps, or command line
- Self-host for complete privacy and control

## 🚀 Quick Start (Local)

### Prerequisites
- Docker and Docker Compose installed
- Linux/macOS/Windows with WSL

### Start NTFY Locally

```bash
# Clone or navigate to this directory
cd /path/to/ntfy

# Start the server
./ntfy-manager.sh start

# Test the server
./ntfy-manager.sh test

# Access web interface: http://localhost:8080
```

### Send a Test Notification

```bash
# Send a basic notification
curl -d "Hello World!" http://localhost:8080/test-topic

# Send with title and emoji
curl -H "Title: Alert!" -d "Server backup completed 🎉" http://localhost:8080/alerts

# Send with priority and tags
curl -H "Priority: high" -H "Tags: warning,backup" -d "Critical backup failure!" http://localhost:8080/alerts
```

## 📱 Mobile App Setup

1. **Install the NTFY app**:
   - Android: [Google Play Store](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
   - iOS: [App Store](https://apps.apple.com/us/app/ntfy/id1625396347)

2. **Subscribe to topics**:
   - Open the app
   - Tap "+" to add a subscription
   - For local: Enter `http://YOUR_LAPTOP_IP:8080/your-topic`
   - For cloud: Enter `https://your-domain.com/your-topic`

## ☁️ Cloud Deployment

### Step 1: DigitalOcean Setup

1. **Install DigitalOcean CLI**:
   ```bash
   # Ubuntu/Debian
   sudo snap install doctl
   
   # Or download from: https://github.com/digitalocean/doctl/releases
   ```

2. **Authenticate**:
   ```bash
   doctl auth init
   # Follow prompts to enter your DigitalOcean API token
   ```

3. **Deploy to DigitalOcean**:
   ```bash
   cd cloud-deployment/digitalocean
   ./deploy.sh --with-ssl
   ```

   This script will:
   - Create a new droplet
   - Install Docker and dependencies
   - Deploy NTFY with Nginx reverse proxy
   - Set up SSL certificates with Let's Encrypt
   - Configure firewall and security

### Step 2: Cloudflare Setup

1. **Configure DNS and Security**:
   ```bash
   cd cloud-deployment/cloudflare
   ./setup.sh setup
   ```

   This will:
   - Create DNS A record pointing to your server
   - Enable SSL/TLS encryption
   - Set up DDoS protection
   - Configure security headers
   - Enable WebSocket support

2. **Test the deployment**:
   ```bash
   ./setup.sh test
   ```

## 🔐 Security Configuration

### Create Admin User (Production)

```bash
# SSH to your server
ssh ntfy@YOUR_SERVER_IP

# Create admin user
docker exec ntfy-server ntfy user add --role=admin admin

# Create regular user
docker exec ntfy-server ntfy user add johndoe

# Set topic permissions
docker exec ntfy-server ntfy access johndoe mytopic rw
docker exec ntfy-server ntfy access johndoe "alerts*" read-only
```

### Authentication Examples

```bash
# Publish with authentication
curl -u admin:password -d "Authenticated message" https://your-domain.com/private-topic

# Subscribe with authentication
curl -u admin:password -s https://your-domain.com/private-topic/sse
```

## 🛠️ Management Commands

### Local Development

```bash
# Start server
./ntfy-manager.sh start

# Stop server
./ntfy-manager.sh stop

# View logs
./ntfy-manager.sh logs

# Check status
./ntfy-manager.sh status

# Create backup
./ntfy-manager.sh backup
```

### Production Server

```bash
# SSH to server
ssh ntfy@YOUR_SERVER_IP

# View logs
docker-compose -f /opt/ntfy/docker-compose.production.yml logs -f

# Restart services
docker-compose -f /opt/ntfy/docker-compose.production.yml restart

# Update NTFY
docker-compose -f /opt/ntfy/docker-compose.production.yml pull
docker-compose -f /opt/ntfy/docker-compose.production.yml up -d
```

## 📋 Configuration Files

### Local Configuration
- `ntfy-config/server.yml` - Basic NTFY configuration
- `docker-compose.yml` - Local Docker setup

### Production Configuration
- `cloud-deployment/ntfy-config/server.yml` - Production NTFY config
- `cloud-deployment/docker-compose.production.yml` - Production Docker setup
- `cloud-deployment/nginx.conf` - Nginx reverse proxy config

## 🔍 Monitoring and Health Checks

### Health Check Endpoint
```bash
curl https://your-domain.com/v1/health
# Returns: {"healthy":true}
```

### Server Monitoring
```bash
# Check server resources
ssh ntfy@YOUR_SERVER_IP 'docker stats'

# Check disk usage
ssh ntfy@YOUR_SERVER_IP 'df -h'

# Check logs for errors
ssh ntfy@YOUR_SERVER_IP 'docker logs ntfy-server | grep ERROR'
```

## 🚨 Troubleshooting

### Common Issues

1. **Can't connect to local server**:
   - Check if Docker is running: `docker ps`
   - Check port conflicts: `sudo netstat -tlnp | grep 8080`
   - Check firewall: `sudo ufw status`

2. **Mobile app can't connect**:
   - Use your laptop's IP address, not `localhost`
   - Check if port 8080 is accessible from network
   - For cloud: ensure DNS has propagated

3. **SSL certificate issues**:
   - Check Cloudflare SSL mode is set to "Full (strict)"
   - Verify DNS propagation: `dig your-domain.com`
   - Check server logs: `docker logs ntfy-nginx`

4. **Authentication problems**:
   - Verify user exists: `docker exec ntfy-server ntfy user list`
   - Check permissions: `docker exec ntfy-server ntfy access username`

### Logs and Debugging

```bash
# Local logs
./ntfy-manager.sh logs

# Production logs
ssh ntfy@YOUR_SERVER_IP 'docker-compose -f /opt/ntfy/docker-compose.production.yml logs -f'

# Enable debug logging (temporarily)
# Edit server.yml and change log-level to "debug"
```

## 📊 Usage Examples

### Basic Notifications
```bash
# Simple message
curl -d "Backup completed" https://your-domain.com/backups

# With title
curl -H "Title: Server Alert" -d "CPU usage high" https://your-domain.com/alerts

# With priority and tags
curl -H "Priority: urgent" -H "Tags: server,cpu" -d "Server down!" https://your-domain.com/alerts
```

### Advanced Features
```bash
# Scheduled delivery
curl -H "At: tomorrow, 8am" -d "Daily report reminder" https://your-domain.com/reminders

# With attachment
curl -T backup.log -H "Filename: backup.log" https://your-domain.com/backups

# Email notification
curl -H "Email: admin@company.com" -d "Critical alert" https://your-domain.com/alerts
```

### Script Integration
```bash
#!/bin/bash
# Backup script with notification

if backup_command; then
    curl -d "Backup successful ✅" https://your-domain.com/backups
else
    curl -H "Priority: high" -H "Tags: warning" \
         -d "Backup failed ❌" https://your-domain.com/alerts
fi
```

## 📁 Directory Structure

```
ntfy/
├── docker-compose.yml              # Local development setup
├── ntfy-manager.sh                 # Local management script
├── ntfy-config/
│   └── server.yml                  # Local configuration
├── ntfy-cache/                     # Local cache directory
├── ntfy-data/                      # Local data directory
└── cloud-deployment/
    ├── docker-compose.production.yml
    ├── nginx.conf
    ├── ntfy-config/
    │   └── server.yml              # Production configuration
    ├── digitalocean/
    │   └── deploy.sh               # DigitalOcean deployment script
    └── cloudflare/
        └── setup.sh                # Cloudflare DNS/SSL setup script
```

## 🔒 Security Best Practices

1. **Enable authentication** in production
2. **Use HTTPS** always (handled by Cloudflare)
3. **Set up firewall** rules (handled by deployment script)
4. **Regular backups** of configuration and data
5. **Monitor logs** for suspicious activity
6. **Keep Docker images updated**

## 🆘 Support

- **NTFY Documentation**: https://docs.ntfy.sh/
- **GitHub Issues**: https://github.com/binwiederhier/ntfy/issues
- **Community**: https://discord.gg/cT7ECsZj9w

## 📝 License

This setup guide is provided as-is. NTFY itself is licensed under Apache 2.0.

---

**Need help?** Check the troubleshooting section or create an issue in the NTFY GitHub repository.
