#!/bin/bash
# Ship test logs using curl and admin session (az login)

set -e

cd terraform
DCR_ENDPOINT=$(terraform output -raw dcr_ingestion_endpoint)
DCR_ID=$(terraform output -raw dcr_immutable_id)
STREAM_NAME=$(terraform output -raw stream_name)
cd ..

echo "=== LA Retention Demo - Test Log Ingestion (Curl) ==="
echo
echo "DCR Endpoint: $DCR_ENDPOINT"
echo "DCR ID: $DCR_ID"
echo "Stream: $STREAM_NAME"
echo

# Get fresh access token
TOKEN=$(az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv)

# Generate timestamps
TIMESTAMP1=$(date -u +"%Y-%m-%dT%H:%M:%S.%6NZ")
sleep 1
TIMESTAMP2=$(date -u +"%Y-%m-%dT%H:%M:%S.%6NZ")

# Test log batch 1 (10 logs)
echo "=== Sending Initial Batch (10 logs) ==="
PAYLOAD1='[
  {"timestamp":"'$TIMESTAMP1'","level":6,"message":"Test log 1/10","test_id":"batch1","sequence":1},
  {"timestamp":"'$TIMESTAMP1'","level":6,"message":"Test log 2/10","test_id":"batch1","sequence":2},
  {"timestamp":"'$TIMESTAMP1'","level":6,"message":"Test log 3/10","test_id":"batch1","sequence":3},
  {"timestamp":"'$TIMESTAMP1'","level":6,"message":"Test log 4/10","test_id":"batch1","sequence":4},
  {"timestamp":"'$TIMESTAMP1'","level":6,"message":"Test log 5/10","test_id":"batch1","sequence":5},
  {"timestamp":"'$TIMESTAMP1'","level":6,"message":"Test log 6/10","test_id":"batch1","sequence":6},
  {"timestamp":"'$TIMESTAMP1'","level":6,"message":"Test log 7/10","test_id":"batch1","sequence":7},
  {"timestamp":"'$TIMESTAMP1'","level":6,"message":"Test log 8/10","test_id":"batch1","sequence":8},
  {"timestamp":"'$TIMESTAMP1'","level":6,"message":"Test log 9/10","test_id":"batch1","sequence":9},
  {"timestamp":"'$TIMESTAMP1'","level":6,"message":"Test log 10/10","test_id":"batch1","sequence":10}
]'

RESPONSE1=$(curl -X POST \
  "${DCR_ENDPOINT}/dataCollectionRules/${DCR_ID}/streams/${STREAM_NAME}?api-version=2023-01-01" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD1" \
  -w "\nHTTP_CODE:%{http_code}" \
  -s)

HTTP_CODE1=$(echo "$RESPONSE1" | grep "HTTP_CODE" | cut -d: -f2)

if [ "$HTTP_CODE1" = "204" ]; then
  echo "✅ Batch 1: Successfully shipped 10 logs - HTTP 204"
else
  echo "❌ Batch 1: Failed - HTTP $HTTP_CODE1"
  echo "$RESPONSE1"
  exit 1
fi

echo
sleep 2

# Test log batch 2 (5 logs)
echo "=== Sending Delta Batch (5 logs) ==="
PAYLOAD2='[
  {"timestamp":"'$TIMESTAMP2'","level":4,"message":"Delta log 1/5 - for export test","test_id":"batch2","sequence":101},
  {"timestamp":"'$TIMESTAMP2'","level":4,"message":"Delta log 2/5 - for export test","test_id":"batch2","sequence":102},
  {"timestamp":"'$TIMESTAMP2'","level":4,"message":"Delta log 3/5 - for export test","test_id":"batch2","sequence":103},
  {"timestamp":"'$TIMESTAMP2'","level":4,"message":"Delta log 4/5 - for export test","test_id":"batch2","sequence":104},
  {"timestamp":"'$TIMESTAMP2'","level":4,"message":"Delta log 5/5 - for export test","test_id":"batch2","sequence":105}
]'

RESPONSE2=$(curl -X POST \
  "${DCR_ENDPOINT}/dataCollectionRules/${DCR_ID}/streams/${STREAM_NAME}?api-version=2023-01-01" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD2" \
  -w "\nHTTP_CODE:%{http_code}" \
  -s)

HTTP_CODE2=$(echo "$RESPONSE2" | grep "HTTP_CODE" | cut -d: -f2)

if [ "$HTTP_CODE2" = "204" ]; then
  echo "✅ Batch 2: Successfully shipped 5 logs - HTTP 204"
else
  echo "❌ Batch 2: Failed - HTTP $HTTP_CODE2"
  echo "$RESPONSE2"
  exit 1
fi

echo
echo "=== Summary ==="
echo "✅ Total logs sent: 15 (10 + 5)"
echo "   Batch 1: test_id='batch1', sequences 1-10"
echo "   Batch 2: test_id='batch2', sequences 101-105"
echo
echo "Next: Wait 2-5 minutes, then run ./verify_retention.sh"
