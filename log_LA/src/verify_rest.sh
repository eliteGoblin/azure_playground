#!/bin/bash
# Direct REST API verification script for DCR log ingestion
# This bypasses any SDK token caching issues

set -e

echo "=== Azure DCR Log Ingestion Verification (REST API) ==="
echo

# Get configuration from Terraform
cd terraform
DCR_ID=$(terraform output -raw dcr_immutable_id)
DCR_ENDPOINT=$(terraform output -raw dcr_ingestion_endpoint)
STREAM_NAME=$(terraform output -raw stream_name)
cd ..

echo "DCR Immutable ID: $DCR_ID"
echo "DCR Endpoint: $DCR_ENDPOINT"
echo "Stream Name: $STREAM_NAME"
echo

# Get a fresh access token
echo "Getting fresh access token..."
TOKEN=$(az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv)
echo "✓ Token acquired"
echo

# Test Case 1: Valid minimal log
echo "--- Test Case 1: Valid Minimal (Flat) Log ---"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%6NZ")
PAYLOAD_1='[{
  "timestamp": "'$TIMESTAMP'",
  "level": 6,
  "message": "Test log entry - minimal flat structure",
  "host": "test-host-01",
  "environment": "dev"
}]'

echo "Sending: $PAYLOAD_1"
curl -X POST \
  "${DCR_ENDPOINT}/dataCollectionRules/${DCR_ID}/streams/${STREAM_NAME}?api-version=2023-01-01" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD_1" \
  -w "\nHTTP Status: %{http_code}\n" \
  -s -S

echo
sleep 1

# Test Case 2: Valid nested log
echo "--- Test Case 2: Valid Nested Log (with attributes) ---"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%6NZ")
PAYLOAD_2='[{
  "timestamp": "'$TIMESTAMP'",
  "level": 4,
  "message": "Test log entry - nested attributes structure",
  "host": "test-host-02",
  "environment": "staging",
  "attributes": {
    "user_id": "12345",
    "request": {
      "method": "POST",
      "path": "/api/v1/orders",
      "duration_ms": 234
    },
    "metadata": {
      "trace_id": "abc-def-123",
      "span_id": "xyz-789",
      "tags": ["payment", "checkout"],
      "nested_object": {
        "level_3": {
          "deep_value": "test_deep_nesting"
        }
      }
    }
  }
}]'

echo "Sending nested log..."
curl -X POST \
  "${DCR_ENDPOINT}/dataCollectionRules/${DCR_ID}/streams/${STREAM_NAME}?api-version=2023-01-01" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD_2" \
  -w "\nHTTP Status: %{http_code}\n" \
  -s -S

echo
sleep 1

# Test Case 3: Invalid log
echo "--- Test Case 3: Invalid Log (unexpected root field) ---"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%6NZ")
PAYLOAD_3='[{
  "timestamp": "'$TIMESTAMP'",
  "level": 3,
  "message": "Test log entry - invalid with unexpected field",
  "host": "test-host-03",
  "environment": "prod",
  "unexpected_field": "This should cause the log to be dropped",
  "another_bad_field": 999
}]'

echo "Sending invalid log (should be accepted by API but dropped by DCR transform)..."
curl -X POST \
  "${DCR_ENDPOINT}/dataCollectionRules/${DCR_ID}/streams/${STREAM_NAME}?api-version=2023-01-01" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD_3" \
  -w "\nHTTP Status: %{http_code}\n" \
  -s -S

echo
echo "=== Summary ==="
echo "HTTP 204 = Success (logs accepted for processing)"
echo "HTTP 403 = Permission denied (RBAC issue)"
echo "HTTP 400 = Bad request (schema/format issue)"
echo
echo "Wait 2-5 minutes, then query Log Analytics:"
echo "  az monitor log-analytics query -w 0617b415-8f69-45c8-a305-ded41ecbcbdc --analytics-query \"corplog_CL | where TimeGenerated > ago(10m)\" -o table"
