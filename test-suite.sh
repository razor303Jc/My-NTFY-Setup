#!/bin/bash

# NTFY Test Suite and Alert System
# This script provides comprehensive testing and automated alert capabilities

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_FILE="$SCRIPT_DIR/message-templates.json"
NTFY_URL="http://localhost:8080"
AUTH_USER_JC="jc:jcpassword123"
AUTH_USER_COPILOT="copilot:copilotpass456"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}==== $1 ====${NC}"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to send notification
send_notification() {
    local title="$1"
    local message="$2"
    local topic="$3"
    local priority="${4:-default}"
    local tags="$5"
    local auth="$6"
    
    local curl_args=()
    
    if [ -n "$auth" ]; then
        curl_args+=("-u" "$auth")
    fi
    
    if [ -n "$title" ]; then
        curl_args+=("-H" "Title: $title")
    fi
    
    if [ -n "$priority" ]; then
        curl_args+=("-H" "Priority: $priority")
    fi
    
    if [ -n "$tags" ]; then
        curl_args+=("-H" "Tags: $tags")
    fi
    
    curl_args+=("-d" "$message")
    curl_args+=("$NTFY_URL/$topic")
    
    curl -s "${curl_args[@]}" | jq -r '.id' 2>/dev/null || echo "Failed to send"
}

# Function to test server connectivity
test_connectivity() {
    print_header "Testing Server Connectivity"
    
    print_step "Testing health endpoint"
    if response=$(curl -s "$NTFY_URL/v1/health"); then
        if echo "$response" | jq -e '.healthy == true' > /dev/null 2>&1; then
            print_success "Server is healthy"
        else
            print_error "Server is not healthy: $response"
            return 1
        fi
    else
        print_error "Cannot connect to NTFY server at $NTFY_URL"
        return 1
    fi
    
    print_step "Testing user authentication"
    if curl -s -u "$AUTH_USER_JC" "$NTFY_URL/test-auth" > /dev/null 2>&1; then
        print_success "User 'jc' authentication working"
    else
        print_warning "User 'jc' authentication may have issues"
    fi
    
    if curl -s -u "$AUTH_USER_COPILOT" "$NTFY_URL/test-auth" > /dev/null 2>&1; then
        print_success "User 'copilot' authentication working"
    else
        print_warning "User 'copilot' authentication may have issues"
    fi
}

# Function to test basic notifications
test_basic_notifications() {
    print_header "Testing Basic Notifications"
    
    print_step "Sending anonymous notification"
    local msg_id=$(send_notification "Test Anonymous" "This is an anonymous test message" "test" "min" "test")
    if [ "$msg_id" != "Failed to send" ]; then
        print_success "Anonymous notification sent (ID: $msg_id)"
    else
        print_error "Failed to send anonymous notification"
    fi
    
    print_step "Sending authenticated notification as jc"
    local msg_id=$(send_notification "Test JC User" "This is a test from user jc" "test" "low" "test,jc" "$AUTH_USER_JC")
    if [ "$msg_id" != "Failed to send" ]; then
        print_success "JC user notification sent (ID: $msg_id)"
    else
        print_error "Failed to send JC user notification"
    fi
    
    print_step "Sending authenticated notification as copilot"
    local msg_id=$(send_notification "Test Copilot User" "This is a test from user copilot" "test" "default" "test,copilot" "$AUTH_USER_COPILOT")
    if [ "$msg_id" != "Failed to send" ]; then
        print_success "Copilot user notification sent (ID: $msg_id)"
    else
        print_error "Failed to send Copilot user notification"
    fi
}

# Function to test different priority levels
test_priority_levels() {
    print_header "Testing Priority Levels"
    
    local priorities=("min" "low" "default" "high" "urgent")
    local emojis=("🔕" "🔔" "📢" "⚠️" "🚨")
    
    for i in "${!priorities[@]}"; do
        local priority="${priorities[$i]}"
        local emoji="${emojis[$i]}"
        
        print_step "Testing priority: $priority"
        local msg_id=$(send_notification "$emoji Priority $priority" "This is a $priority priority test message" "priority-test" "$priority" "test,priority")
        if [ "$msg_id" != "Failed to send" ]; then
            print_success "Priority $priority notification sent (ID: $msg_id)"
        else
            print_error "Failed to send priority $priority notification"
        fi
        sleep 1
    done
}

# Function to test template-based notifications
test_template_notifications() {
    print_header "Testing Template-Based Notifications"
    
    if [ ! -f "$TEMPLATES_FILE" ]; then
        print_error "Templates file not found: $TEMPLATES_FILE"
        return 1
    fi
    
    print_step "Testing system alert template"
    local msg_id=$(send_notification "🚨 Server Alert" "Server web-01 is down" "alerts" "urgent" "alert,server,critical" "$AUTH_USER_JC")
    if [ "$msg_id" != "Failed to send" ]; then
        print_success "System alert sent (ID: $msg_id)"
    fi
    
    print_step "Testing backup success template"
    local msg_id=$(send_notification "✅ Backup Successful" "Backup of database-prod completed successfully at $(date)" "backups" "low" "backup,success" "$AUTH_USER_JC")
    if [ "$msg_id" != "Failed to send" ]; then
        print_success "Backup success notification sent (ID: $msg_id)"
    fi
    
    print_step "Testing deployment notification"
    local msg_id=$(send_notification "🚀 Deployment Successful" "ntfy-server v2.13.0 deployed successfully to production" "deployments" "low" "deployment,success" "$AUTH_USER_JC")
    if [ "$msg_id" != "Failed to send" ]; then
        print_success "Deployment notification sent (ID: $msg_id)"
    fi
    
    print_step "Testing security alert"
    local msg_id=$(send_notification "🔐 Failed Login Attempt" "Failed login attempt for user admin from IP 192.168.1.100" "security" "high" "security,login,warning" "$AUTH_USER_JC")
    if [ "$msg_id" != "Failed to send" ]; then
        print_success "Security alert sent (ID: $msg_id)"
    fi
}

# Function to test emoji and special characters
test_special_characters() {
    print_header "Testing Emoji and Special Characters"
    
    local test_messages=(
        "🎉 Party time! Test with emojis 🚀"
        "Special chars: âéîôû ñç €£¥ ©®™"
        "Code: \`echo 'hello world'\`"
        "Multiline\nmessage\ntest"
        "JSON: {\"key\": \"value\", \"number\": 42}"
    )
    
    for i in "${!test_messages[@]}"; do
        local msg="${test_messages[$i]}"
        print_step "Testing message $((i+1)): ${msg:0:30}..."
        
        local msg_id=$(send_notification "Special Chars Test $((i+1))" "$msg" "special-test" "min" "test,special")
        if [ "$msg_id" != "Failed to send" ]; then
            print_success "Special characters test $((i+1)) sent (ID: $msg_id)"
        else
            print_error "Failed to send special characters test $((i+1))"
        fi
        sleep 1
    done
}

# Function to test bulk notifications
test_bulk_notifications() {
    print_header "Testing Bulk Notifications"
    
    print_step "Sending 10 rapid notifications"
    for i in {1..10}; do
        local msg_id=$(send_notification "Bulk Test $i" "This is bulk notification number $i of 10" "bulk-test" "min" "test,bulk")
        if [ "$msg_id" != "Failed to send" ]; then
            echo -n "."
        else
            echo -n "X"
        fi
    done
    echo ""
    print_success "Bulk notification test completed"
}

# Function to simulate real-world alerts
simulate_real_alerts() {
    print_header "Simulating Real-World Alerts"
    
    print_step "Simulating server monitoring alerts"
    
    # High CPU alert
    send_notification "⚠️ High CPU Usage" "CPU usage on web-01 is 87% (threshold: 80%)" "system" "high" "warning,cpu,performance" "$AUTH_USER_JC" > /dev/null
    sleep 2
    
    # Memory warning
    send_notification "🧠 High Memory Usage" "Memory usage on web-01 is 92%" "system" "default" "warning,memory" "$AUTH_USER_JC" > /dev/null
    sleep 2
    
    # Backup notification
    send_notification "✅ Backup Successful" "Daily backup of database-prod completed successfully" "backups" "low" "backup,success" "$AUTH_USER_JC" > /dev/null
    sleep 2
    
    # Security alert
    send_notification "👀 Suspicious Activity" "Multiple failed login attempts detected from IP 203.0.113.42" "security" "urgent" "security,suspicious,critical" "$AUTH_USER_JC" > /dev/null
    sleep 2
    
    # SSL expiry warning
    send_notification "🔒 SSL Certificate Expiring" "SSL certificate for ntfy.example.com expires in 7 days" "certificates" "high" "ssl,certificate,expiry" "$AUTH_USER_JC" > /dev/null
    
    print_success "Real-world alert simulation completed"
}

# Function to generate automated alerts based on system metrics
generate_system_alerts() {
    print_header "Generating Automated System Alerts"
    
    print_step "Checking system metrics"
    
    # CPU usage check
    if command -v top >/dev/null 2>&1; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
        if (( $(echo "$cpu_usage > 80" | bc -l 2>/dev/null || echo 0) )); then
            send_notification "⚠️ High CPU Usage" "Current CPU usage is ${cpu_usage}%" "system" "high" "warning,cpu" "$AUTH_USER_JC" > /dev/null
            print_warning "High CPU usage detected: ${cpu_usage}%"
        fi
    fi
    
    # Disk usage check
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 80 ]; then
        send_notification "💾 Low Disk Space" "Root partition is ${disk_usage}% full" "system" "high" "warning,disk,storage" "$AUTH_USER_JC" > /dev/null
        print_warning "Low disk space detected: ${disk_usage}%"
    else
        print_success "Disk usage is normal: ${disk_usage}%"
    fi
    
    # Memory usage check
    if command -v free >/dev/null 2>&1; then
        local mem_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
        if (( $(echo "$mem_usage > 85" | bc -l 2>/dev/null || echo 0) )); then
            send_notification "🧠 High Memory Usage" "Current memory usage is ${mem_usage}%" "system" "default" "warning,memory" "$AUTH_USER_JC" > /dev/null
            print_warning "High memory usage detected: ${mem_usage}%"
        else
            print_success "Memory usage is normal: ${mem_usage}%"
        fi
    fi
    
    # Docker container check
    if command -v docker >/dev/null 2>&1; then
        local container_count=$(docker ps -q | wc -l)
        local stopped_containers=$(docker ps -aq --filter "status=exited" | wc -l)
        
        send_notification "📊 Container Status" "Running containers: $container_count, Stopped: $stopped_containers" "monitoring" "low" "docker,containers" "$AUTH_USER_COPILOT" > /dev/null
        print_success "Container status reported: $container_count running, $stopped_containers stopped"
    fi
}

# Function to run performance tests
test_performance() {
    print_header "Testing Performance"
    
    print_step "Testing message delivery speed"
    local start_time=$(date +%s%N)
    
    for i in {1..50}; do
        send_notification "Perf Test $i" "Performance test message $i" "perf-test" "min" "test,performance" > /dev/null
    done
    
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    local messages_per_second=$(( 50000 / duration ))
    
    print_success "Sent 50 messages in ${duration}ms (~${messages_per_second} msg/sec)"
    
    # Send performance report
    send_notification "📈 Performance Test Results" "Sent 50 messages in ${duration}ms (~${messages_per_second} msg/sec)" "reports" "low" "performance,test" "$AUTH_USER_COPILOT" > /dev/null
}

# Function to show usage
show_usage() {
    echo "NTFY Test Suite and Alert System"
    echo "================================"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  full-test        - Run complete test suite"
    echo "  connectivity     - Test server connectivity"
    echo "  basic           - Test basic notifications"
    echo "  priorities      - Test priority levels"
    echo "  templates       - Test template-based notifications"
    echo "  special-chars   - Test emoji and special characters"
    echo "  bulk            - Test bulk notifications"
    echo "  simulate        - Simulate real-world alerts"
    echo "  system-alerts   - Generate system-based alerts"
    echo "  performance     - Run performance tests"
    echo "  demo            - Send demo notifications for all users"
    echo ""
    echo "Examples:"
    echo "  $0 full-test"
    echo "  $0 system-alerts"
    echo "  $0 demo"
}

# Function to run demo notifications
run_demo() {
    print_header "Running Demo Notifications"
    
    print_step "Sending welcome messages"
    send_notification "👋 Welcome JC!" "Your NTFY server is ready! You have admin access to all topics." "welcome" "default" "welcome,admin" "$AUTH_USER_JC" > /dev/null
    send_notification "🤖 Welcome Copilot!" "I'm ready to help monitor your systems and send automated alerts." "welcome" "default" "welcome,ai" "$AUTH_USER_COPILOT" > /dev/null
    
    print_step "Sending sample alerts"
    send_notification "🎉 Setup Complete" "NTFY server setup completed successfully! Users: jc (admin), copilot (user)" "setup" "low" "setup,complete" "$AUTH_USER_JC" > /dev/null
    
    print_success "Demo notifications sent!"
    echo ""
    echo "Check your NTFY web interface at: $NTFY_URL"
    echo "Subscribe to topics: welcome, setup, test, alerts, system, backups"
}

# Main function
main() {
    case "${1:-help}" in
        full-test)
            test_connectivity
            echo ""
            test_basic_notifications
            echo ""
            test_priority_levels
            echo ""
            test_template_notifications
            echo ""
            test_special_characters
            echo ""
            test_bulk_notifications
            echo ""
            simulate_real_alerts
            echo ""
            generate_system_alerts
            echo ""
            test_performance
            ;;
        connectivity)
            test_connectivity
            ;;
        basic)
            test_basic_notifications
            ;;
        priorities)
            test_priority_levels
            ;;
        templates)
            test_template_notifications
            ;;
        special-chars)
            test_special_characters
            ;;
        bulk)
            test_bulk_notifications
            ;;
        simulate)
            simulate_real_alerts
            ;;
        system-alerts)
            generate_system_alerts
            ;;
        performance)
            test_performance
            ;;
        demo)
            run_demo
            ;;
        help|*)
            show_usage
            ;;
    esac
}

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
    print_warning "jq is not installed. Some features may not work properly."
    print_warning "Install with: sudo apt install jq"
fi

# Run main function
main "$@"
