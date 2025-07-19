#!/bin/bash

# NTFY Automated Alert Scheduler
# This script runs automated alerts and system monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NTFY_URL="http://localhost:8080"
AUTH_USER_JC="jc:jcpassword123"
AUTH_USER_COPILOT="copilot:copilotpass456"
LOG_FILE="$SCRIPT_DIR/automation.log"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to send notification with error handling
send_alert() {
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
    
    curl_args+=("-s" "-d" "$message")
    curl_args+=("$NTFY_URL/$topic")
    
    if response=$(curl "${curl_args[@]}" 2>/dev/null); then
        local msg_id=$(echo "$response" | jq -r '.id' 2>/dev/null || echo "unknown")
        log_message "Sent: $title (ID: $msg_id)"
        return 0
    else
        log_message "ERROR: Failed to send: $title"
        return 1
    fi
}

# System monitoring alerts
check_system_health() {
    log_message "Running system health check..."
    
    # CPU check
    if command -v top >/dev/null 2>&1; then
        local cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/%id,//')
        local cpu_usage=$(echo "100 - $cpu_idle" | bc -l 2>/dev/null || echo "0")
        local cpu_int=${cpu_usage%.*}
        
        if [ "$cpu_int" -gt 80 ]; then
            send_alert "⚠️ High CPU Usage" "CPU usage is ${cpu_int}% (threshold: 80%)" "system" "high" "warning,cpu,performance" "$AUTH_USER_JC"
        elif [ "$cpu_int" -gt 60 ]; then
            send_alert "📊 CPU Status" "CPU usage is ${cpu_int}%" "monitoring" "low" "cpu,monitoring" "$AUTH_USER_COPILOT"
        fi
    fi
    
    # Memory check
    if command -v free >/dev/null 2>&1; then
        local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
        
        if [ "$mem_usage" -gt 85 ]; then
            send_alert "🧠 High Memory Usage" "Memory usage is ${mem_usage}% (threshold: 85%)" "system" "high" "warning,memory" "$AUTH_USER_JC"
        elif [ "$mem_usage" -gt 70 ]; then
            send_alert "📊 Memory Status" "Memory usage is ${mem_usage}%" "monitoring" "low" "memory,monitoring" "$AUTH_USER_COPILOT"
        fi
    fi
    
    # Disk space check
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$disk_usage" -gt 90 ]; then
        send_alert "💾 Critical Disk Space" "Root partition is ${disk_usage}% full" "system" "urgent" "critical,disk,storage" "$AUTH_USER_JC"
    elif [ "$disk_usage" -gt 80 ]; then
        send_alert "💾 Low Disk Space" "Root partition is ${disk_usage}% full" "system" "high" "warning,disk,storage" "$AUTH_USER_JC"
    elif [ "$disk_usage" -gt 70 ]; then
        send_alert "📊 Disk Status" "Root partition is ${disk_usage}% full" "monitoring" "low" "disk,monitoring" "$AUTH_USER_COPILOT"
    fi
    
    # Docker container check
    if command -v docker >/dev/null 2>&1; then
        local running_containers=$(docker ps -q | wc -l)
        local total_containers=$(docker ps -aq | wc -l)
        local stopped_containers=$((total_containers - running_containers))
        
        if [ "$stopped_containers" -gt 5 ]; then
            send_alert "🐳 Many Stopped Containers" "Found $stopped_containers stopped containers" "docker" "default" "docker,containers" "$AUTH_USER_COPILOT"
        fi
        
        # Check NTFY container specifically
        if ! docker ps | grep -q ntfy-server; then
            send_alert "🚨 NTFY Container Down" "NTFY server container is not running!" "alerts" "urgent" "critical,docker,ntfy" "$AUTH_USER_JC"
        fi
    fi
    
    log_message "System health check completed"
}

# Send daily status report
send_daily_report() {
    log_message "Generating daily status report..."
    
    local uptime_info=$(uptime | awk '{print $3,$4}' | sed 's/,//')
    local load_avg=$(uptime | awk '{print $(NF-2) $(NF-1) $NF}')
    local disk_usage=$(df / | awk 'NR==2 {print $5}')
    local mem_usage=$(free | awk 'NR==2{printf "%.0f%%", $3*100/$2}')
    
    local report="System Status Report:
- Uptime: $uptime_info
- Load average: $load_avg
- Disk usage: $disk_usage
- Memory usage: $mem_usage
- Time: $(date)"
    
    send_alert "📋 Daily System Report" "$report" "reports" "low" "report,daily,system" "$AUTH_USER_JC"
    
    log_message "Daily report sent"
}

# Test NTFY server health
test_ntfy_health() {
    log_message "Testing NTFY server health..."
    
    if ! curl -s "$NTFY_URL/v1/health" | jq -e '.healthy == true' > /dev/null 2>&1; then
        send_alert "🚨 NTFY Health Check Failed" "NTFY server health check failed at $(date)" "alerts" "urgent" "critical,ntfy,health" "$AUTH_USER_JC"
        return 1
    fi
    
    # Test authentication
    if ! curl -s -u "$AUTH_USER_JC" "$NTFY_URL/test-auth" > /dev/null 2>&1; then
        send_alert "🔐 NTFY Auth Issue" "NTFY authentication test failed for user jc" "alerts" "high" "warning,ntfy,auth" "$AUTH_USER_JC"
        return 1
    fi
    
    log_message "NTFY server health check passed"
    return 0
}

# Send backup reminders
send_backup_reminders() {
    local hour=$(date +%H)
    
    # Send backup reminder at 2 AM
    if [ "$hour" = "02" ]; then
        send_alert "💾 Backup Reminder" "Time for daily backup at $(date)" "backups" "default" "reminder,backup" "$AUTH_USER_JC"
        log_message "Backup reminder sent"
    fi
}

# Monitor log files for errors
check_log_errors() {
    local docker_logs=$(docker logs ntfy-server --since=1h 2>&1 | grep -i error | wc -l)
    
    if [ "$docker_logs" -gt 10 ]; then
        send_alert "📋 High Error Rate" "Found $docker_logs errors in NTFY logs in the last hour" "monitoring" "high" "warning,logs,errors" "$AUTH_USER_JC"
        log_message "High error rate detected: $docker_logs errors"
    fi
}

# Send heartbeat (every hour)
send_heartbeat() {
    local minute=$(date +%M)
    
    # Send heartbeat at the top of every hour
    if [ "$minute" = "00" ]; then
        send_alert "💓 System Heartbeat" "Automation system is running normally at $(date)" "heartbeat" "min" "automation,heartbeat" "$AUTH_USER_COPILOT"
        log_message "Heartbeat sent"
    fi
}

# Main monitoring function
run_monitoring() {
    log_message "Starting monitoring cycle..."
    
    # Always run these checks
    test_ntfy_health
    check_system_health
    check_log_errors
    send_heartbeat
    
    # Time-based checks
    local hour=$(date +%H)
    local minute=$(date +%M)
    
    # Daily report at 8 AM
    if [ "$hour" = "08" ] && [ "$minute" = "00" ]; then
        send_daily_report
    fi
    
    # Backup reminders
    send_backup_reminders
    
    log_message "Monitoring cycle completed"
}

# Simulation mode for testing
run_simulation() {
    log_message "Running simulation mode..."
    
    # Simulate various alerts
    send_alert "🧪 Simulation: High CPU" "Simulated high CPU usage: 87%" "system" "high" "simulation,cpu" "$AUTH_USER_JC"
    sleep 2
    
    send_alert "🧪 Simulation: Backup Success" "Simulated successful backup completion" "backups" "low" "simulation,backup" "$AUTH_USER_JC"
    sleep 2
    
    send_alert "🧪 Simulation: Security Alert" "Simulated failed login attempt from 192.168.1.100" "security" "high" "simulation,security" "$AUTH_USER_JC"
    sleep 2
    
    send_alert "🧪 Simulation: Deployment" "Simulated successful deployment of app v1.2.3" "deployments" "low" "simulation,deployment" "$AUTH_USER_JC"
    
    log_message "Simulation completed"
}

# Show usage
show_usage() {
    echo "NTFY Automated Alert Scheduler"
    echo "=============================="
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  monitor     - Run single monitoring cycle"
    echo "  daemon      - Run continuous monitoring (every 5 minutes)"
    echo "  simulate    - Run simulation with test alerts"
    echo "  health      - Test NTFY server health only"
    echo "  system      - Run system health check only"
    echo "  report      - Send daily report now"
    echo "  heartbeat   - Send heartbeat now"
    echo "  logs        - Show automation logs"
    echo ""
    echo "Examples:"
    echo "  $0 monitor"
    echo "  $0 daemon &     # Run in background"
    echo "  $0 simulate"
}

# Daemon mode
run_daemon() {
    log_message "Starting automation daemon..."
    echo "Automation daemon started. Check logs: tail -f $LOG_FILE"
    
    while true; do
        run_monitoring
        sleep 300  # 5 minutes
    done
}

# Main function
main() {
    # Ensure log file exists
    touch "$LOG_FILE"
    
    case "${1:-help}" in
        monitor)
            run_monitoring
            ;;
        daemon)
            run_daemon
            ;;
        simulate)
            run_simulation
            ;;
        health)
            test_ntfy_health
            ;;
        system)
            check_system_health
            ;;
        report)
            send_daily_report
            ;;
        heartbeat)
            send_alert "💓 Manual Heartbeat" "Manual heartbeat sent at $(date)" "heartbeat" "min" "manual,heartbeat" "$AUTH_USER_COPILOT"
            ;;
        logs)
            if [ -f "$LOG_FILE" ]; then
                tail -20 "$LOG_FILE"
            else
                echo "No logs found"
            fi
            ;;
        help|*)
            show_usage
            ;;
    esac
}

# Check dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not installed"
    exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
    echo "ERROR: bc is required but not installed"
    exit 1
fi

# Run main function
main "$@"
