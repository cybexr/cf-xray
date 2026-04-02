#!/bin/bash
# Test script to validate Xray configuration template

set -e

echo "=== Xray Configuration Template Test ==="

# Test environment variables
export VLESS_UUID="12345678-1234-1234-1234-123456789abc"
export DOMAIN="test.example.com"
export PORT="10000"
export LOG_LEVEL="warning"
export VLESS_XHTTP_PATH="/xhttp-secret-path-test"
export TLS_CERT_FILE="/etc/xray/certs/fullchain.pem"
export TLS_KEY_FILE="/etc/xray/certs/privkey.pem"

echo ""
echo "Test 1: Validate JSON structure"
echo "--------------------------------"
# Read template and substitute variables
sed -e "s/\${VLESS_UUID}/${VLESS_UUID}/g" \
    -e "s/\${DOMAIN}/${DOMAIN}/g" \
    -e "s/\${PORT:-10000}/${PORT}/g" \
    -e "s/\${LOG_LEVEL:-warning}/${LOG_LEVEL}/g" \
    -e "s#\${VLESS_XHTTP_PATH}#${VLESS_XHTTP_PATH}#g" \
    -e "s#\${TLS_CERT_FILE}#${TLS_CERT_FILE}#g" \
    -e "s#\${TLS_KEY_FILE}#${TLS_KEY_FILE}#g" \
    config/xray-template.json > /tmp/test-config.json

# Validate JSON
if python3 -m json.tool /tmp/test-config.json > /dev/null 2>&1; then
    echo "✓ Valid JSON structure"
else
    echo "✗ Invalid JSON structure"
    exit 1
fi

echo ""
echo "Test 2: Check required fields"
echo "------------------------------"
# Check for required fields
required_fields=("inbounds" "outbounds" "routing")
for field in "${required_fields[@]}"; do
    if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if sys.argv[2] in d else 1)" /tmp/test-config.json "${field}" > /dev/null 2>&1; then
        echo "✓ Field '${field}' exists"
    else
        echo "✗ Field '${field}' missing"
        exit 1
    fi
done

echo ""
echo "Test 3: Verify VLESS configuration"
echo "-----------------------------------"
# Check VLESS protocol
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['protocol'] == 'vless' else 1)" /tmp/test-config.json > /dev/null 2>&1; then
    echo "✓ VLESS protocol configured"
else
    echo "✗ VLESS protocol not found"
    exit 1
fi

# Check UUID substitution
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['settings']['clients'][0]['id'] == sys.argv[2] else 1)" /tmp/test-config.json "${VLESS_UUID}" > /dev/null 2>&1; then
    echo "✓ UUID correctly substituted"
else
    echo "✗ UUID substitution failed"
    exit 1
fi

# Check XHTTP network
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['network'] == 'xhttp' else 1)" /tmp/test-config.json > /dev/null 2>&1; then
    echo "✓ XHTTP transport configured"
else
    echo "✗ XHTTP transport not found"
    exit 1
fi

# Check VLESS_XHTTP_PATH
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['xhttpSettings']['path'] == sys.argv[2] else 1)" /tmp/test-config.json "${VLESS_XHTTP_PATH}" > /dev/null 2>&1; then
    echo "✓ VLESS_XHTTP_PATH correctly set"
else
    echo "✗ VLESS_XHTTP_PATH mismatch"
    exit 1
fi

echo ""
echo "Test 4: Verify TLS configuration"
echo "---------------------------------"
# Check TLS security
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['security'] == 'tls' else 1)" /tmp/test-config.json > /dev/null 2>&1; then
    echo "✓ TLS security enabled"
else
    echo "✗ TLS security not configured"
    exit 1
fi

# Check TLS settings
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if 'tlsSettings' in d['inbounds'][0]['streamSettings'] else 1)" /tmp/test-config.json > /dev/null 2>&1; then
    echo "✓ TLS settings configured"
else
    echo "✗ TLS settings missing"
    exit 1
fi

# Check certificate file path
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['tlsSettings']['certificates'][0]['certificateFile'] == sys.argv[2] else 1)" /tmp/test-config.json "${TLS_CERT_FILE}" > /dev/null 2>&1; then
    echo "✓ Certificate file path correctly set"
else
    echo "✗ Certificate file path mismatch"
    exit 1
fi

# Check key file path
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if d['inbounds'][0]['streamSettings']['tlsSettings']['certificates'][0]['keyFile'] == sys.argv[2] else 1)" /tmp/test-config.json "${TLS_KEY_FILE}" > /dev/null 2>&1; then
    echo "✓ Private key file path correctly set"
else
    echo "✗ Private key file path mismatch"
    exit 1
fi

echo ""
echo "Test 5: Verify outbound configuration"
echo "--------------------------------------"
if python3 -c "import json, sys; d = json.load(open(sys.argv[1])); exit(0 if len(d['outbounds']) > 0 else 1)" /tmp/test-config.json > /dev/null 2>&1; then
    echo "✓ Outbound configured"
else
    echo "✗ Outbound missing"
    exit 1
fi

echo ""
echo "Test 6: Display generated config"
echo "---------------------------------"
python3 -m json.tool /tmp/test-config.json

echo ""
echo "=== All Tests Passed ==="
echo "Template is valid and ready for use"

# Cleanup
rm -f /tmp/test-config.json
