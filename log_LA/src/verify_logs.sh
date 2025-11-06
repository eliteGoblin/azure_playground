#!/bin/bash
# Verify logs in Log Analytics and check DCR metrics

set -e

echo "=== Verifying Logs in Log Analytics ==="
echo

# Get workspace ID from Terraform
cd terraform
WORKSPACE_ID=$(terraform output -raw workspace_id)
cd ..

echo "Workspace ID: $WORKSPACE_ID"
echo

# Get access token
TOKEN=$(az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv)

# Query Log Analytics
echo "Querying corplog_CL table for recent logs..."
echo

QUERY='corplog_CL | where TimeGenerated > ago(24h) | project TimeGenerated, level, message, host, environment, attributes | order by TimeGenerated desc'

curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"${QUERY}\"}" | jq -r '
    if .tables then
      .tables[0] |
      "Found \(.rows | length) log entries:\n" +
      "=" * 80 + "\n" +
      (.columns | map(.name) | join(" | ")) + "\n" +
      "-" * 80 + "\n" +
      (.rows | map(join(" | ")) | join("\n"))
    else
      "No data returned or error: " + (. | tostring)
    end
  '

echo
echo

# Check if we got any results
RESULT=$(curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"corplog_CL | where TimeGenerated > ago(24h) | count\"}")

COUNT=$(echo "$RESULT" | jq -r '.tables[0].rows[0][0] // 0')

echo "=== Summary ==="
echo "Total logs in last 24 hours: $COUNT"
echo

if [ "$COUNT" -eq 0 ]; then
  echo "⚠️  No logs found yet. This could mean:"
  echo "  1. Ingestion is still processing (wait 2-5 more minutes)"
  echo "  2. Logs were dropped by DCR transform"
  echo "  3. Check DCR metrics for errors"
else
  echo "✓ Logs successfully ingested into Log Analytics!"

  # Check for nested attributes
  echo
  echo "Checking nested attributes..."
  ATTR_QUERY='corplog_CL | where TimeGenerated > ago(24h) and isnotnull(attributes) | project message, attributes | take 1'

  curl -s -X POST \
    "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"${ATTR_QUERY}\"}" | jq -r '
      if .tables[0].rows | length > 0 then
        "✓ Found log with nested attributes:\n" +
        "Message: " + (.tables[0].rows[0][0] | tostring) + "\n" +
        "Attributes: " + (.tables[0].rows[0][1] | tostring)
      else
        "No logs with attributes found"
      end
    '
fi

echo
