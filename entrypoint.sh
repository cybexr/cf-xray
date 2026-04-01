#!/bin/sh
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function to validate required environment variables
validate_env() {
    local required_vars="TUNNEL_TOKEN VLESS_UUID DOMAIN"
    local missing_vars=""

    for var in $required_vars; do
        eval "value=\${$var}"
        if [ -z "$value" ]; then
            missing_vars="$missing_vars $var"
        fi
    done

    if [ -n "$missing_vars" ]; then
        log_error "Missing required environment variables:$missing_vars"
        log_error "Please set the following environment variables:"
        echo "  - TUNNEL_TOKEN: Your Cloudflare Tunnel token"
        echo "  - VLESS_UUID: Your VLESS UUID for client authentication"
        echo "  - DOMAIN: Your domain for Cloudflare Tunnel"
        exit 1
    fi

    log_info "All required environment variables are set"
}

# Function to generate Xray configuration
generate_config() {
    local template_path="/etc/xray/xray-template.json"
    local config_path="/etc/xray/config.json"

    if [ ! -f "$template_path" ]; then
        log_error "Template file not found: $template_path"
        exit 1
    fi

    log_info "Generating Xray configuration from template"

    # Read template and substitute environment variables
    sed -e "s/\${VLESS_UUID}/${VLESS_UUID}/g" \
        -e "s/\${DOMAIN}/${DOMAIN}/g" \
        -e "s/\${PORT:-10000}/${PORT:-10000}/g" \
        -e "s/\${LOG_LEVEL:-warning}/${LOG_LEVEL:-warning}/g" \
        -e "s#\${VLESS_XHTTP_PATH:-/your-secret-path}#${VLESS_XHTTP_PATH:-/your-secret-path}#g" \
        "$template_path" > "$config_path"

    log_info "Configuration generated at $config_path"
}

# Function to start cloudflared
start_cloudflared() {
    log_info "Starting cloudflared in background"

    nohup cloudflared tunnel --no-autoupdate run --token "${TUNNEL_TOKEN}" > /tmp/cloudflared.log 2>&1 &
    CLOUDFLARED_PID=$!

    # Wait a bit to ensure cloudflared starts
    sleep 2

    if ! kill -0 $CLOUDFLARED_PID 2>/dev/null; then
        log_error "Failed to start cloudflared"
        cat /tmp/cloudflared.log
        exit 1
    fi

    log_info "cloudflared started with PID: $CLOUDFLARED_PID"
}

# Function to start xray
start_xray() {
    log_info "Starting xray in foreground"

    exec xray run -config /etc/xray/config.json
}

# Function to handle signals
cleanup() {
    log_info "Received shutdown signal, cleaning up..."

    if [ -n "$CLOUDFLARED_PID" ]; then
        log_info "Stopping cloudflared (PID: $CLOUDFLARED_PID)"
        kill $CLOUDFLARED_PID 2>/dev/null || true
        wait $CLOUDFLARED_PID 2>/dev/null || true
    fi

    log_info "Shutdown complete"
    exit 0
}

# Function to start health check server
start_health_check() {
    if [ "${ENABLE_HEALTH_CHECK:-true}" = "true" ]; then
        log_info "Starting health check server on port 8080"

        # Simple health check endpoint using netcat if available
        if command -v nc >/dev/null 2>&1; then
            (
                while true; do
                    echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"healthy\"}" | nc -l -p 8080 >/dev/null 2>&1
                done
            ) &
            HEALTH_CHECK_PID=$!
            log_info "Health check server started with PID: $HEALTH_CHECK_PID"
        else
            log_warn "netcat not available, health check server disabled"
        fi
    fi
}

# Main execution
main() {
    log_info "Starting Xray + cloudflared container"
    log_info "Xray-core version: $(xray version | head -n 1 || echo 'unknown')"
    log_info "cloudflared version: $(cloudflared --version 2>&1 || echo 'unknown')"

    # Validate environment variables
    validate_env

    # Generate Xray configuration
    generate_config

    # Start health check server
    start_health_check

    # Start cloudflared in background
    start_cloudflared

    # Set signal handlers
    trap cleanup SIGTERM SIGINT

    # Start xray in foreground (this will block)
    start_xray
}

# Run main function
main
