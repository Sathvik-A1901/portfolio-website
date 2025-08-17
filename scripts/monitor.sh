#!/bin/bash

# Website Monitoring Script
# Monitors portfolio website availability and performance
# Author: Sathvik Addicharla
# Date: 2024

# Configuration
WEBSITE_URL="https://your-portfolio-domain.com"
LOG_FILE="website_monitor.log"
ALERT_EMAIL="sathvik.addicharla@gmail.com"
CHECK_INTERVAL=300  # 5 minutes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to send email alert
send_alert() {
    local subject="$1"
    local message="$2"
    
    if command -v mail &> /dev/null; then
        echo "$message" | mail -s "$subject" "$ALERT_EMAIL"
    elif command -v sendmail &> /dev/null; then
        echo "Subject: $subject" > /tmp/alert_email.txt
        echo "" >> /tmp/alert_email.txt
        echo "$message" >> /tmp/alert_email.txt
        sendmail "$ALERT_EMAIL" < /tmp/alert_email.txt
        rm /tmp/alert_email.txt
    else
        log_message "WARNING: Email sending not available. Install mailutils or sendmail."
    fi
}

# Function to check website availability
check_availability() {
    local url="$1"
    local response_code
    local response_time
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_message "ERROR: curl is not installed. Please install curl to monitor website."
        return 1
    fi
    
    # Perform the check with timeout
    local start_time=$(date +%s.%N)
    
    # Use curl to check website with timeout
    local curl_output=$(curl -s -w "%{http_code}|%{time_total}" --max-time 30 --connect-timeout 10 "$url" 2>/dev/null)
    local exit_code=$?
    
    local end_time=$(date +%s.%N)
    local total_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    if [ $exit_code -eq 0 ]; then
        response_code=$(echo "$curl_output" | tail -1 | cut -d'|' -f1)
        response_time=$(echo "$curl_output" | tail -1 | cut -d'|' -f2)
        
        if [ "$response_code" = "200" ]; then
            log_message "✅ Website is UP - HTTP $response_code - Response time: ${response_time}s"
            return 0
        else
            log_message "⚠️  Website returned HTTP $response_code - Response time: ${response_time}s"
            send_alert "Website Warning" "Website returned HTTP $response_code. Response time: ${response_time}s"
            return 1
        fi
    else
        log_message "❌ Website is DOWN - Connection failed (exit code: $exit_code)"
        send_alert "Website Down Alert" "Website is currently down. Connection failed with exit code: $exit_code"
        return 1
    fi
}

# Function to check website performance
check_performance() {
    local url="$1"
    
    if ! command -v curl &> /dev/null; then
        return 1
    fi
    
    # Check load time
    local load_time=$(curl -s -w "%{time_total}" --max-time 30 --connect-timeout 10 "$url" -o /dev/null 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Convert to milliseconds
        local load_time_ms=$(echo "$load_time * 1000" | bc -l 2>/dev/null || echo "0")
        local load_time_ms_int=$(printf "%.0f" "$load_time_ms")
        
        if [ "$load_time_ms_int" -lt 1000 ]; then
            log_message "🚀 Performance: Excellent (${load_time_ms_int}ms)"
        elif [ "$load_time_ms_int" -lt 2000 ]; then
            log_message "⚡ Performance: Good (${load_time_ms_int}ms)"
        elif [ "$load_time_ms_int" -lt 3000 ]; then
            log_message "🐌 Performance: Fair (${load_time_ms_int}ms)"
        else
            log_message "🐌 Performance: Poor (${load_time_ms_int}ms)"
            send_alert "Performance Alert" "Website performance is poor. Load time: ${load_time_ms_int}ms"
        fi
    fi
}

# Function to check SSL certificate
check_ssl() {
    local url="$1"
    local domain=$(echo "$url" | sed 's|https://||' | sed 's|http://||' | sed 's|/.*||')
    
    if ! command -v openssl &> /dev/null; then
        log_message "WARNING: openssl not available. Cannot check SSL certificate."
        return 1
    fi
    
    local ssl_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local not_after=$(echo "$ssl_info" | grep "notAfter" | cut -d'=' -f2)
        local expiry_date=$(date -d "$not_after" +%s 2>/dev/null || echo "0")
        local current_date=$(date +%s)
        local days_until_expiry=$(( (expiry_date - current_date) / 86400 ))
        
        if [ "$days_until_expiry" -gt 30 ]; then
            log_message "🔒 SSL: Valid (expires in $days_until_expiry days)"
        elif [ "$days_until_expiry" -gt 7 ]; then
            log_message "⚠️  SSL: Expiring soon (expires in $days_until_expiry days)"
            send_alert "SSL Expiry Warning" "SSL certificate expires in $days_until_expiry days"
        else
            log_message "❌ SSL: Expires soon (expires in $days_until_expiry days)"
            send_alert "SSL Expiry Alert" "SSL certificate expires in $days_until_expiry days"
        fi
    else
        log_message "❌ SSL: Cannot verify certificate"
    fi
}

# Function to check disk space
check_disk_space() {
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$disk_usage" -lt 80 ]; then
        log_message "💾 Disk: Healthy (${disk_usage}% used)"
    elif [ "$disk_usage" -lt 90 ]; then
        log_message "⚠️  Disk: Warning (${disk_usage}% used)"
        send_alert "Disk Space Warning" "Disk usage is at ${disk_usage}%"
    else
        log_message "❌ Disk: Critical (${disk_usage}% used)"
        send_alert "Disk Space Alert" "Disk usage is critical at ${disk_usage}%"
    fi
}

# Function to check memory usage
check_memory() {
    if command -v free &> /dev/null; then
        local mem_info=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
        
        if [ "$mem_info" -lt 80 ]; then
            log_message "🧠 Memory: Healthy (${mem_info}% used)"
        elif [ "$mem_info" -lt 90 ]; then
            log_message "⚠️  Memory: Warning (${mem_info}% used)"
        else
            log_message "❌ Memory: Critical (${mem_info}% used)"
            send_alert "Memory Alert" "Memory usage is critical at ${mem_info}%"
        fi
    fi
}

# Function to generate status report
generate_report() {
    local report_file="status_report_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "=== Website Status Report ===" > "$report_file"
    echo "Generated: $(date)" >> "$report_file"
    echo "Website: $WEBSITE_URL" >> "$report_file"
    echo "" >> "$report_file"
    
    # Check availability
    echo "=== Availability Check ===" >> "$report_file"
    if check_availability "$WEBSITE_URL"; then
        echo "Status: UP" >> "$report_file"
    else
        echo "Status: DOWN" >> "$report_file"
    fi
    
    # Check performance
    echo "" >> "$report_file"
    echo "=== Performance Check ===" >> "$report_file"
    check_performance "$WEBSITE_URL" >> "$report_file" 2>&1
    
    # Check SSL
    echo "" >> "$report_file"
    echo "=== SSL Certificate Check ===" >> "$report_file"
    check_ssl "$WEBSITE_URL" >> "$report_file" 2>&1
    
    # System resources
    echo "" >> "$report_file"
    echo "=== System Resources ===" >> "$report_file"
    check_disk_space >> "$report_file" 2>&1
    check_memory >> "$report_file" 2>&1
    
    log_message "📊 Status report generated: $report_file"
}

# Function to show help
show_help() {
    echo "Website Monitoring Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --check         Perform a single check"
    echo "  -m, --monitor       Start continuous monitoring"
    echo "  -r, --report        Generate status report"
    echo "  -u, --url URL       Set website URL to monitor"
    echo "  -i, --interval SEC  Set check interval in seconds"
    echo ""
    echo "Examples:"
    echo "  $0 --check                    # Single check"
    echo "  $0 --monitor                  # Start monitoring"
    echo "  $0 --url https://example.com  # Monitor specific URL"
    echo "  $0 --interval 60              # Check every 60 seconds"
}

# Main function
main() {
    local mode="check"
    local url="$WEBSITE_URL"
    local interval="$CHECK_INTERVAL"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--check)
                mode="check"
                shift
                ;;
            -m|--monitor)
                mode="monitor"
                shift
                ;;
            -r|--report)
                mode="report"
                shift
                ;;
            -u|--url)
                url="$2"
                shift 2
                ;;
            -i|--interval)
                interval="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Create log file if it doesn't exist
    touch "$LOG_FILE"
    
    log_message "🚀 Starting website monitoring for: $url"
    
    case $mode in
        "check")
            log_message "📋 Performing single check..."
            check_availability "$url"
            check_performance "$url"
            check_ssl "$url"
            check_disk_space
            check_memory
            ;;
        "monitor")
            log_message "🔄 Starting continuous monitoring (interval: ${interval}s)..."
            while true; do
                check_availability "$url"
                check_performance "$url"
                check_ssl "$url"
                check_disk_space
                check_memory
                echo "----------------------------------------"
                sleep "$interval"
            done
            ;;
        "report")
            log_message "📊 Generating status report..."
            generate_report
            ;;
    esac
    
    log_message "✅ Monitoring completed"
}

# Run main function with all arguments
main "$@"
