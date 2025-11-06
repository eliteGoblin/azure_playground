#!/bin/bash
# Find where the logs actually went

set -e

cd terraform
WORKSPACE_ID=$(terraform output -raw workspace_id)
cd ..

TOKEN=$(az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv)

echo "=== Searching for Logs in Workspace ==="
echo "Workspace ID: $WORKSPACE_ID"
echo

# 1. List all tables with "corp" or "CL" suffix
echo "1. Tables containing 'corp' or ending with '_CL':"
curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"query": "search * | distinct $table | where $table contains \"corp\" or $table endswith \"_CL\""}' | \
  jq -r '.tables[0].rows[][]' 2>/dev/null | sort

echo

# 2. Check for data in last 24 hours across all custom tables
echo "2. Checking all custom tables (_CL suffix) with data in last 24h:"
curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"query": "search * | where TimeGenerated > ago(24h) | distinct $table | where $table endswith \"_CL\""}' | \
  jq -r '.tables[0].rows[][]' 2>/dev/null | sort

echo

# 3. Try exact table name query
echo "3. Querying corplog_CL directly (all rows count):"
RESULT=$(curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"query": "corplog_CL | count"}')

echo "$RESULT" | jq -r '.tables[0].rows[0][0] // "Error or no data"'

echo

# 4. Check if there are ANY logs with our test messages
echo "4. Searching for our test messages across ALL tables (last 24h):"
curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"query": "search \"Test log entry\" | where TimeGenerated > ago(24h) | distinct $table, TimeGenerated | take 10"}' | \
  jq -r '
    if .tables[0].rows | length > 0 then
      "Found logs in:\n" +
      (.tables[0].rows | map(join(" | ")) | join("\n"))
    else
      "No logs found with test message"
    end
  '

echo
echo "=== Search Complete ==="
