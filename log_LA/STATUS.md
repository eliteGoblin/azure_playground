# Azure DCR Log Ingestion Demo - Current Status

## ✅ Successfully Completed

1. **Infrastructure Provisioned (Terraform)**
   - Resource Group: `rg-la-dcr-demo`
   - Log Analytics Workspace: `law-dcr-demo` (ID: `0617b415-8f69-45c8-a305-ded41ecbcbdc`)
   - Data Collection Endpoint: `dce-corplog-demo`
   - Data Collection Rule: `dcr-corplog-demo` (ID: `dcr-fc14b18db04a4f63bcaf325378ab3ad5`)
   - Custom Table: `corplog_CL`
   - User-Assigned Managed Identity: `uami-dcr-demo`
   - RBAC: Admin user has "Monitoring Metrics Publisher" role on DCR

2. **Python Client Created**
   - `ship_logs.py` - Uses admin credentials (az login) to send logs
   - Successfully sent 3 test logs (API returned HTTP 204 success)

3. **Verification Scripts Created**
   - `verify_logs.sh` - Queries Log Analytics
   - `diagnose.sh` - Comprehensive diagnostics

## ⚠️ Current Issue

**Logs are not appearing in Log Analytics**
- Logs were successfully accepted by the DCR API (HTTP 204)
- But query `corplog_CL` returns 0 rows
- Table exists and query succeeds, just no data

## 🔍 Diagnostic Results

```
DCR Configuration:
  - Input Stream: Custom-CorpLog
  - Output Stream: Custom-corplog_CL
  - Transform KQL: source | extend TimeGenerated = timestamp | project-away timestamp
  - Table: corplog_CL

Status:
  - ✓ Table exists in workspace
  - ✓ Table query succeeds
  - ✗ Table has 0 rows
  - ✓ Logs sent successfully (HTTP 204)
```

## 🐛 Likely Root Causes

1. **Output Stream Name Mismatch**
   - DCR output stream: `Custom-corplog_CL`
   - Table name: `corplog_CL`
   - Azure may expect exact case matching or different format

2. **Table Schema Mismatch**
   - DCR transform might not match table schema exactly
   - Table was created via Azure CLI, not Terraform resource

3. **DCR Transform Dropping Logs**
   - Transform KQL might be silently failing
   - No error metrics being generated

## 📋 Next Steps for Debugging

### Option 1: Recreate with Correct Configuration
```bash
# Destroy current DCR (keeps table)
terraform destroy -target=azurerm_monitor_data_collection_rule.demo

# Fix output stream format and recreate
# Research correct output stream naming for DCR-based custom tables
```

### Option 2: Check Azure Portal
1. Go to Azure Portal → Data Collection Rules → `dcr-corplog-demo`
2. Check "Logs" tab for any ingestion errors
3. Check "Metrics" for RowsReceived/RowsDropped
4. View the actual DCR JSON configuration

### Option 3: Use Azure Monitor Agent Test
```bash
# Send a test log via Azure REST API with detailed error response
curl -X POST \
  "https://dce-corplog-demo-bb72.australiaeast-1.ingest.monitor.azure.com/dataCollectionRules/dcr-fc14b18db04a4f63bcaf325378ab3ad5/streams/Custom-CorpLog?api-version=2023-01-01" \
  -H "Authorization: Bearer $(az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv)" \
  -H "Content-Type: application/json" \
  -d '[{"timestamp":"2025-11-06T02:00:00Z","level":6,"message":"test","host":"test","environment":"dev"}]' \
  -v
```

### Option 4: Query Ingestion Logs
```kql
// In Azure Portal Log Analytics workspace
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.INSIGHTS"
| where ResourceType == "DATACOLLECTIONRULES"
| where TimeGenerated > ago(1h)
```

## 📁 Generated Files

- `/log_LA/src/terraform/` - Infrastructure as code
- `/log_LA/src/ship_logs.py` - Log shipping script (admin credentials)
- `/log_LA/src/verify_logs.sh` - Log verification script
- `/log_LA/src/diagnose.sh` - Diagnostics script
- `/log_LA/src/requirements.txt` - Python dependencies

## 🔧 Quick Commands

```bash
# Re-ship logs
cd log_LA/src
python3 ship_logs.py

# Verify logs (wait 2-5 min after shipping)
./verify_logs.sh

# Run diagnostics
./diagnose.sh

# View Terraform state
cd terraform
terraform show
terraform output
```

## 💡 Key Learnings

1. **UAMI Limitation**: UAMI can only authenticate from Azure resources (VMs, Container Instances, etc.), not from local machines
2. **Admin Credentials**: Using `az login` (DefaultAzureCredential) works for local testing
3. **DCR Output Stream**: The output stream naming format is critical and cannot be easily changed after creation
4. **Ingestion Latency**: Normal ingestion takes 2-5 minutes, but we've waited 5+ minutes with no results

## 📚 References

- [Azure Monitor Data Collection Rules](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Logs Ingestion API](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-ingestion-api-overview)
- [Custom Logs via DCR](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/tutorial-logs-ingestion-portal)
