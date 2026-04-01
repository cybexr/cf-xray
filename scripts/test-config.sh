#!/bin/bash
# Test script to validate Xray configuration template

set -e

echo "=== Xray Configuration Template Test ==="

# Test environment variables
export VLESS_UUID="12345678-1234-1234-1234-123456789abc"
export DOMAIN="test.example.com"
export PORT="10000"
export LOG_LEVEL="warning"

echo ""
echo "Test 1: Validate JSON structure"
echo "--------------------------------"
# Read template and substitute variables
sed -e "s/\${VLESS_UUID}/${VLESS_UUID}/g" \
    -e "s/\${DOMAIN}/${DOMAIN}/g" \
    -e "s/\${PORT:-10000}/${PORT}/g" \
    -e "s/\${LOG_LEVEL:-warning}/${LOG_LEVEL}/g" \
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
    if jq -e ".${field}" /tmp/test-config.json > /dev/null 2>&1; then
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
if jq -e '.inbounds[0].protocol == "vless"' /tmp/test-config.json > /dev/null 2>&1; then
    echo "✓ VLESS protocol configured"
else
    echo "✗ VLESS protocol not found"
    exit 1
fi

# Check UUID substitution
if jq -e '.inbounds[0].settings.clients[0].id == "'${VLESS_UUID}'"' /tmp/test-config.json > /dev/null 2>&1; then
    echo "✓ UUID correctly substituted"
else
    echo "✗ UUID substitution failed"
    exit 1
fi

# Check XHTTP network
if jq -e '.inbounds[0].streamSettings.network == "xhttp"' /tmp/test-config.json > /dev/null 2>&1; then
    echo "✓ XHTTP transport configured"
else
    echo "✗ XHTTP transport not found"
    exit 1
fi

echo ""
echo "Test 4: Verify outbound configuration"
echo "--------------------------------------"
if jq -e '.outbounds | length > 0' /tmp/test-config.json > /dev/null 2>&1; then
    echo "✓ Outbound configured"
else
    echo "✗ Outbound missing"
    exit 1
fi

echo ""
echo "Test 5: Display generated config"
echo "---------------------------------"
jq '.' /tmp/test-config.json

echo ""
echo "=== All Tests Passed ==="
echo "Template is valid and ready for use"

# Cleanup
rm -f /tmp/test-config.json
