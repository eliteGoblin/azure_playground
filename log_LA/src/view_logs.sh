#!/bin/bash
# View all ingested logs with full details

cd terraform
WORKSPACE_ID=$(terraform output -raw workspace_id)
cd ..

TOKEN=$(az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv)

echo "=== All Logs in corplog_CL (last 24 hours) ===="
echo

# Query all logs
RESULT=$(curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"query": "corplog_CL | where TimeGenerated > ago(24h) | project TimeGenerated, level, message, host, environment, attributes | order by TimeGenerated asc"}')

echo "$RESULT" | jq -r '
  .tables[0] |
  "Total Logs: " + (.rows | length | tostring) + "\n" +
  "=" * 80 + "\n" +
  (.columns | map(.name) | join(" | ")) + "\n" +
  "-" * 80 + "\n" +
  (.rows | map(. | @json) | join("\n"))
'

echo
echo "=== Detailed View of Each Log ==="
echo

# Show each log in detail
echo "$RESULT" | jq -r '
  .tables[0] |
  .rows |
  to_entries |
  map(
    "\n--- Log " + ((.key + 1) | tostring) + " ---\n" +
    "TimeGenerated: " + .value[0] + "\n" +
    "Level: " + (.value[1] | tostring) + "\n" +
    "Message: " + .value[2] + "\n" +
    "Host: " + .value[3] + "\n" +
    "Environment: " + .value[4] + "\n" +
    "Attributes: " + (.value[5] | tostring)
  ) |
  join("\n")
'

echo
echo "=== Checking for Nested Attributes ==="
echo

# Check logs with attributes
ATTR_RESULT=$(curl -s -X POST \
  "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"query": "corplog_CL | where TimeGenerated > ago(24h) and isnotnull(attributes) | project message, attributes"}')

echo "$ATTR_RESULT" | jq -r '
  if .tables[0].rows | length > 0 then
    .tables[0].rows |
    map("Message: " + .[0] + "\nAttributes JSON:\n" + .[1]) |
    join("\n\n")
  else
    "No logs with attributes found"
  end
'

echo
