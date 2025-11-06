#!/bin/bash
# Comprehensive diagnostic script

echo "=== Azure DCR Ingestion Diagnostics ==="
echo

# Get configuration
cd terraform
DCR_ID=$(terraform output -raw dcr_immutable_id)
WORKSPACE_ID=$(terraform output -raw workspace_id)
TABLE_NAME=$(terraform output -raw table_name)
cd ..

echo "Configuration:"
echo "  DCR ID: $DCR_ID"
echo "  Workspace ID: $WORKSPACE_ID"
echo "  Table Name: $TABLE_NAME"
echo

# Check 1: Does the table exist?
echo "1. Checking if table '$TABLE_NAME' exists and has data..."
TOKEN=$(az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv)

# Try to query the table directly - if it succeeds, table exists
RESPONSE=$(curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"$TABLE_NAME | getschema | take 1\"}")

ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty' 2>/dev/null)

if [ -n "$ERROR" ]; then
  echo "❌ Table not found or error: $ERROR"
elif echo "$RESPONSE" | jq -e '.tables[0]' > /dev/null 2>&1; then
  echo "✓ Table '$TABLE_NAME' exists and is queryable"
else
  echo "❌ Unexpected response from Log Analytics"
fi
echo

# Check 2: Query the table directly
echo "2. Attempting to query $TABLE_NAME directly..."
DIRECT=$(curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"$TABLE_NAME | take 1\"}" | jq -r '.error.message // "Query succeeded"')

echo "Result: $DIRECT"
echo

# Check 3: Count all rows
echo "3. Counting all rows in $TABLE_NAME..."
COUNT=$(curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"$TABLE_NAME | count\"}" | jq -r '.tables[0].rows[0][0] // "error"')

echo "Total rows: $COUNT"
echo

# Check 4: Check DCR configuration
echo "4. Checking DCR configuration..."
az monitor data-collection rule show \
  --name dcr-corplog-demo \
  --resource-group rg-la-dcr-demo \
  --query "{Transform:dataFlows[0].transformKql, OutputStream:dataFlows[0].outputStream, Streams:dataFlows[0].streams}" \
  -o json | jq '.'

echo
echo "=== Diagnostics Complete ==="
