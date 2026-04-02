#!/bin/bash
# Test script to validate Xray configuration generation

set -e

echo "=== Xray Configuration Generation Test ==="

# Test environment variables
export VLESS_UUID="12345678-1234-1234-1234-123456789abc"
export DOMAIN="test.example.com"
export PORT="10000"
export LOG_LEVEL="warning"
export VLESS_XHTTP_PATH="/xhttp-secret-path-test"
export TLS_CERT_FILE="/etc/xray/certs/fullchain.pem"
export TLS_KEY_FILE="/etc/xray/certs/privkey.pem"

log_info() { echo "[INFO] $1"; }

generate_config() {
    local config_path="/tmp/xray-test-config.json"

    if [ "${TLS_ENABLED:-true}" != "false" ] && [ "${TLS_ENABLED:-true}" != "none" ]; then
        log_info "TLS enabled for Xray inbound"
        cat > "$config_path" << EOF
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
EOF
    else
        log_info "TLS disabled for Xray inbound (Cloudflare Tunnel mode)"
        cat > "$config_path" << EOF
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
EOF
    fi
}

echo ""
echo "Test 1: Test TLS_ENABLED=false (Cloudflare Tunnel mode)"
echo "--------------------------------------------------------"
TLS_ENABLED="false"
generate_config
config_json="/tmp/xray-test-config.json"

if [ ! -f "$config_json" ]; then
    echo "✗ Config file not generated"
    exit 1
fi

# Validate JSON
if python3 -m json.tool "$config_json" > /dev/null 2>&1; then
    echo "✓ Valid JSON structure"
else
    echo "✗ Invalid JSON structure"
    cat "$config_json"
    exit 1
fi

# Check security is none
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['security'] == 'none' else 1)" "$config_json" > /dev/null 2>&1; then
    echo "✓ TLS disabled (security: none)"
else
    echo "✗ TLS should be disabled"
    exit 1
fi

# Check no tlsSettings
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(1 if 'tlsSettings' in d['inbounds'][0]['streamSettings'] else 0)" "$config_json" > /dev/null 2>&1; then
    echo "✓ No TLS settings (as expected)"
else
    echo "✗ TLS settings should not exist"
    exit 1
fi

echo ""
echo "Test 2: Test TLS_ENABLED=true (Direct TLS mode)"
echo "-----------------------------------------------"
TLS_ENABLED="true"
generate_config

# Validate JSON
if python3 -m json.tool "$config_json" > /dev/null 2>&1; then
    echo "✓ Valid JSON structure"
else
    echo "✗ Invalid JSON structure"
    cat "$config_json"
    exit 1
fi

# Check security is tls
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['security'] == 'tls' else 1)" "$config_json" > /dev/null 2>&1; then
    echo "✓ TLS enabled (security: tls)"
else
    echo "✗ TLS should be enabled"
    exit 1
fi

# Check tlsSettings exists
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if 'tlsSettings' in d['inbounds'][0]['streamSettings'] else 1)" "$config_json" > /dev/null 2>&1; then
    echo "✓ TLS settings configured"
else
    echo "✗ TLS settings missing"
    exit 1
fi

# Check certificate file path
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['tlsSettings']['certificates'][0]['certificateFile'] == '$TLS_CERT_FILE' else 1)" "$config_json" > /dev/null 2>&1; then
    echo "✓ Certificate file path correctly set"
else
    echo "✗ Certificate file path mismatch"
    exit 1
fi

# Check key file path
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['tlsSettings']['certificates'][0]['keyFile'] == '$TLS_KEY_FILE' else 1)" "$config_json" > /dev/null 2>&1; then
    echo "✓ Private key file path correctly set"
else
    echo "✗ Private key file path mismatch"
    exit 1
fi

echo ""
echo "Test 3: Verify common configuration"
echo "------------------------------------"
# Check VLESS protocol
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['protocol'] == 'vless' else 1)" "$config_json" > /dev/null 2>&1; then
    echo "✓ VLESS protocol configured"
else
    echo "✗ VLESS protocol not found"
    exit 1
fi

# Check UUID substitution
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['settings']['clients'][0]['id'] == '$VLESS_UUID' else 1)" "$config_json" > /dev/null 2>&1; then
    echo "✓ UUID correctly set"
else
    echo "✗ UUID mismatch"
    exit 1
fi

# Check XHTTP network
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['network'] == 'xhttp' else 1)" "$config_json" > /dev/null 2>&1; then
    echo "✓ XHTTP transport configured"
else
    echo "✗ XHTTP transport not found"
    exit 1
fi

# Check VLESS_XHTTP_PATH
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['xhttpSettings']['path'] == '$VLESS_XHTTP_PATH' else 1)" "$config_json" > /dev/null 2>&1; then
    echo "✓ VLESS_XHTTP_PATH correctly set"
else
    echo "✗ VLESS_XHTTP_PATH mismatch"
    exit 1
fi

echo ""
echo "Test 4: Verify outbound configuration"
echo "--------------------------------------"
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if len(d['outbounds']) > 0 else 1)" "$config_json" > /dev/null 2>&1; then
    echo "✓ Outbound configured"
else
    echo "✗ Outbound missing"
    exit 1
fi

echo ""
echo "=== All Tests Passed ==="
echo "Configuration generation is valid and ready for use"

# Cleanup
rm -f "$config_json"
