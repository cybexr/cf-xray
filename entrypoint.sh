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
    local required_vars="TUNNEL_TOKEN VLESS_UUID DOMAIN VLESS_XHTTP_PATH"
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
        echo "  - VLESS_XHTTP_PATH: Your secret path for XHTTP transport"
        exit 1
    fi

    log_info "All required environment variables are set"
}

# Function to validate PEM content
validate_pem_content() {
    local file="$1"
    local type="$2"  # "cert" or "key"

    # Check for PEM headers
    if [ "$type" = "cert" ]; then
        if ! grep -q "BEGIN CERTIFICATE" "$file" 2>/dev/null; then
            log_error "Certificate file does not contain valid PEM data (missing BEGIN CERTIFICATE): $file"
            log_error "Please mount a valid certificate file"
            return 1
        fi
        if ! grep -q "END CERTIFICATE" "$file" 2>/dev/null; then
            log_error "Certificate file does not contain valid PEM data (missing END CERTIFICATE): $file"
            return 1
        fi
    else
        if ! grep -q "BEGIN.*PRIVATE KEY" "$file" 2>/dev/null && \
           ! grep -q "BEGIN RSA PRIVATE KEY" "$file" 2>/dev/null && \
           ! grep -q "BEGIN EC PRIVATE KEY" "$file" 2>/dev/null && \
           ! grep -q "BEGIN PRIVATE KEY" "$file" 2>/dev/null; then
            log_error "Key file does not contain valid PEM data (missing BEGIN PRIVATE KEY): $file"
            log_error "Please mount a valid private key file"
            return 1
        fi
        if ! grep -q "END.*PRIVATE KEY" "$file" 2>/dev/null && \
           ! grep -q "END RSA PRIVATE KEY" "$file" 2>/dev/null && \
           ! grep -q "END EC PRIVATE KEY" "$file" 2>/dev/null && \
           ! grep -q "END PRIVATE KEY" "$file" 2>/dev/null; then
            log_error "Key file does not contain valid PEM data (missing END PRIVATE KEY): $file"
            return 1
        fi
    fi

    return 0
}

# Function to validate certificate files
setup_certs() {
    # Check if TLS is disabled
    if [ "${TLS_ENABLED:-true}" = "false" ] || [ "${TLS_ENABLED:-true}" = "none" ]; then
        log_info "TLS is disabled, skipping certificate validation"
        return 0
    fi

    # Set default paths if not specified
    TLS_CERT_FILE="${TLS_CERT_FILE:-/etc/xray/certs/fullchain.pem}"
    TLS_KEY_FILE="${TLS_KEY_FILE:-/etc/xray/certs/privkey.pem}"

    # Validate certificate files exist and are non-empty
    if [ ! -f "$TLS_CERT_FILE" ]; then
        log_error "TLS certificate file not found: $TLS_CERT_FILE"
        log_error "Please mount your certificate file or set TLS_CERT_FILE"
        log_error "Example docker-compose.yml volume:"
        log_error "  - ./path/to/fullchain.pem:/etc/xray/certs/fullchain.pem:ro"
        exit 1
    fi

    if [ ! -s "$TLS_CERT_FILE" ]; then
        log_error "TLS certificate file is empty: $TLS_CERT_FILE"
        log_error "Please mount a valid certificate file"
        exit 1
    fi

    if [ ! -r "$TLS_CERT_FILE" ]; then
        log_error "TLS certificate file is not readable by current user: $TLS_CERT_FILE"
        exit 1
    fi

    # Validate PEM content
    if ! validate_pem_content "$TLS_CERT_FILE" "cert"; then
        exit 1
    fi

    if [ ! -f "$TLS_KEY_FILE" ]; then
        log_error "TLS private key file not found: $TLS_KEY_FILE"
        log_error "Please mount your private key file or set TLS_KEY_FILE"
        log_error "Example docker-compose.yml volume:"
        log_error "  - ./path/to/privkey.pem:/etc/xray/certs/privkey.pem:ro"
        exit 1
    fi

    if [ ! -s "$TLS_KEY_FILE" ]; then
        log_error "TLS private key file is empty: $TLS_KEY_FILE"
        log_error "Please mount a valid private key file"
        exit 1
    fi

    if [ ! -r "$TLS_KEY_FILE" ]; then
        log_error "TLS private key file is not readable by current user: $TLS_KEY_FILE"
        exit 1
    fi

    # Validate PEM content
    if ! validate_pem_content "$TLS_KEY_FILE" "key"; then
        exit 1
    fi

    log_info "Certificate files validated: $TLS_CERT_FILE, $TLS_KEY_FILE"
}


# Function to generate Xray configuration
generate_config() {
    local config_path="/etc/xray/config.json"

    log_info "Generating Xray configuration from template"

    # Handle TLS settings based on TLS_ENABLED
    if [ "${TLS_ENABLED:-true}" != "false" ] && [ "${TLS_ENABLED:-true}" != "none" ]; then
        # TLS enabled
        log_info "TLS enabled for Xray inbound"
        cat > "$config_path" << 'CONFIG'
{
  "log": {
    "loglevel": "${LOG_LEVEL:-warning}",
    "access": "none"
  },
  "inbounds": [
    {
      "port": ${PORT:-10000},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${VLESS_UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${TLS_CERT_FILE}",
              "keyFile": "${TLS_KEY_FILE}"
            }
          ],
          "serverName": "${DOMAIN}"
        },
        "xhttpSettings": {
          "path": "${VLESS_XHTTP_PATH}",
          "mode": "auto",
          "noSNIHeader": false
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
        "domainStrategy": "AsIs"
      }
    },
    {
      "protocol": "blackhole",
      "tag": "block",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
CONFIG
    else
        # TLS disabled (Cloudflare Tunnel mode)
        log_info "TLS disabled for Xray inbound (Cloudflare Tunnel mode)"
        cat > "$config_path" << 'CONFIG'
{
  "log": {
    "loglevel": "${LOG_LEVEL:-warning}",
    "access": "none"
  },
  "inbounds": [
    {
      "port": ${PORT:-10000},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${VLESS_UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "path": "${VLESS_XHTTP_PATH}",
          "mode": "auto",
          "noSNIHeader": false
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
        "domainStrategy": "AsIs"
      }
    },
    {
      "protocol": "blackhole",
      "tag": "block",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
CONFIG
    fi

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
    
    # Check if we're running a custom command
    if [ $# -gt 0 ] && [ "$1" != "xray" ] && [ "$1" != "/entrypoint.sh" ]; then
        log_info "Executing custom command: $@"
        exec "$@"
    fi

    # For xray commands or default startup, we need config
    if [ "$1" = "xray" ]; then
        # If it's just 'xray version', don't require env vars or generate config
        if [ "$2" = "version" ]; then
            exec "$@"
        fi

        # Set default TLS paths for xray commands too
        TLS_CERT_FILE="${TLS_CERT_FILE:-/etc/xray/certs/fullchain.pem}"
        TLS_KEY_FILE="${TLS_KEY_FILE:-/etc/xray/certs/privkey.pem}"

        # For other xray commands (like -test), try to generate config if possible
        # but don't exit if env vars are missing unless they are actually needed
        generate_config 2>/dev/null || log_warn "Could not generate config (missing env vars?)"
        exec "$@"
    fi

    log_info "Xray-core version: $(xray version | head -n 1 || echo 'unknown')"
    log_info "cloudflared version: $(cloudflared --version 2>&1 || echo 'unknown')"

    # Validate environment variables
    validate_env

    # Setup certificate files
    setup_certs

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

# Run main function with all arguments
main "$@"
