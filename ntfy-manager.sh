#!/bin/bash

# NTFY Management Script
# Usage: ./ntfy-manager.sh [start|stop|restart|logs|status|test]

set -e

case "$1" in
    start)
        echo "Starting NTFY server..."
        docker-compose up -d
        echo "NTFY server started! Access it at: http://localhost:8080"
        echo "Wait a moment for the service to be ready, then run: ./ntfy-manager.sh test"
        ;;
    
    stop)
        echo "Stopping NTFY server..."
        docker-compose down
        echo "NTFY server stopped."
        ;;
    
    restart)
        echo "Restarting NTFY server..."
        docker-compose down
        docker-compose up -d
        echo "NTFY server restarted!"
        ;;
    
    logs)
        echo "Showing NTFY server logs (Ctrl+C to exit)..."
        docker-compose logs -f ntfy
        ;;
    
    status)
        echo "NTFY server status:"
        docker-compose ps
        echo ""
        echo "Health check:"
        curl -s http://localhost:8080/v1/health | jq . 2>/dev/null || curl -s http://localhost:8080/v1/health
        ;;
    
    test)
        echo "Testing NTFY server..."
        echo "1. Sending test notification..."
        
        # Test basic notification
        response=$(curl -s -d "Hello from your local NTFY server! 🎉" http://localhost:8080/test-topic)
        echo "   Response: $response"
        
        echo ""
        echo "2. You can subscribe to the test topic in several ways:"
        echo "   - Web: http://localhost:8080"
        echo "   - CLI: ntfy subscribe localhost:8080/test-topic"
        echo "   - Phone app: Add server 'http://your-laptop-ip:8080' and subscribe to 'test-topic'"
        echo ""
        echo "3. Send more notifications:"
        echo "   curl -d 'Your message' http://localhost:8080/your-topic"
        ;;
    
    shell)
        echo "Opening shell in NTFY container..."
        docker-compose exec ntfy sh
        ;;
    
    backup)
        echo "Creating backup of NTFY data..."
        timestamp=$(date +"%Y%m%d_%H%M%S")
        tar -czf "ntfy-backup-$timestamp.tar.gz" ntfy-cache ntfy-data ntfy-config
        echo "Backup created: ntfy-backup-$timestamp.tar.gz"
        ;;
    
    *)
        echo "NTFY Management Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  start    - Start NTFY server"
        echo "  stop     - Stop NTFY server"
        echo "  restart  - Restart NTFY server"
        echo "  logs     - Show server logs"
        echo "  status   - Show server status and health"
        echo "  test     - Test the server with a sample notification"
        echo "  shell    - Open shell in container"
        echo "  backup   - Create backup of all data"
        echo ""
        echo "Examples:"
        echo "  $0 start"
        echo "  $0 test"
        echo "  $0 logs"
        ;;
esac
