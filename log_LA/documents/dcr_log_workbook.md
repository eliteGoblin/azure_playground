# DCR Log Ingestion - Workbook

Quick reference for using the demo implementation.

## Project Structure

```
log_LA/src/
├── terraform/
│   ├── main.tf              # Infrastructure: RG, LAW, table, DCR, DCE, UAMI
│   ├── outputs.tf           # Exposes: dcr_immutable_id, dcr_ingestion_endpoint, stream_name, workspace_id
│   └── terraform.tfstate    # State file (gitignored)
│
├── ship_logs.py             # Python SDK client - sends 3 test logs
├── requirements.txt         # Python deps: azure-monitor-ingestion, azure-identity
│
├── diagnose.sh              # Check if table exists, DCR config, row count
├── find_logs.sh             # Search for logs across all tables
├── verify_logs.sh           # Primary verification - shows ingestion + nested attrs
├── view_logs.sh             # Detailed view of each log with attributes JSON
├── verify_rest.sh           # Alternative: direct REST API (bypasses SDK)
└── test_queries.sh          # Test all KQL examples from solution doc
```

## Quick Start

### 1. Provision Infrastructure
```bash
cd log_LA/src/terraform
terraform init
terraform apply -auto-approve

# Check outputs
terraform output
```

**What's created**:
- Resource Group: `rg-la-dcr-demo`
- LA Workspace: `law-dcr-demo`
- Custom Table: `corplog_CL` (via Azure CLI)
- DCR: `dcr-corplog-demo` (stream: Custom-CorpLog, transform KQL)
- DCE: `dce-corplog-demo` (ingestion endpoint)
- UAMI: `uami-dcr-demo` (for production use)

### 2. Ship Logs
```bash
cd log_LA/src

# Install Python dependencies (once)
pip3 install -r requirements.txt

# Send test logs (requires: az login)
python3 ship_logs.py
```

**What's sent**:
- Log 1: Flat structure (dev, level=6)
- Log 2: Nested attributes (staging, level=4, complex JSON)
- Log 3: Unknown fields (prod, level=3, unexpected_field dropped)

Expected output: `HTTP 204` for all 3 logs.

### 3. Verify Logs (wait 2-10 minutes)
```bash
# Primary verification
./verify_logs.sh

# Detailed view
./view_logs.sh

# Search across all tables
./find_logs.sh

# Check table + DCR config
./diagnose.sh
```

## Verification Scripts

### diagnose.sh
**Purpose**: Check infrastructure is working.

**What it checks**:
1. Does table `corplog_CL` exist and is queryable?
2. Can we query the table directly?
3. How many total rows?
4. What's the DCR transform KQL?

**Expected output**:
```
✓ Table 'corplog_CL' exists and is queryable
Result: Query succeeded
Total rows: 3
Transform: source | extend TimeGenerated = timestamp | project-away timestamp
```

---

### find_logs.sh
**Purpose**: Locate logs when unsure where they went.

**What it does**:
1. List all tables with 'corp' or '_CL' suffix
2. Find custom tables with data in last 24h
3. Query corplog_CL row count
4. Search for test message across all tables

**Use when**: Logs not appearing in expected table.

---

### verify_logs.sh
**Purpose**: Primary verification - confirm ingestion + nested attributes.

**What it shows**:
1. All logs in last 24h with columns displayed
2. Total count
3. Sample log with nested attributes preserved

**Expected output**:
```
Found 3 log entries:
...
Total logs in last 24 hours: 3
✓ Logs successfully ingested into Log Analytics!
✓ Found log with nested attributes:
Attributes: {"user_id":"12345","request":{...},"metadata":{...}}
```

---

### view_logs.sh
**Purpose**: Detailed view of each log individually.

**What it shows**:
1. Table view of all logs
2. Detailed view with each field on separate line
3. Attributes as formatted JSON

**Use when**: Need to inspect specific log content.

---

### verify_rest.sh
**Purpose**: Alternative ingestion using raw REST API (not SDK).

**What it does**:
- Sends same 3 test logs via `curl` directly to DCR endpoint
- Useful if SDK has issues or for understanding raw API

**Use when**: Troubleshooting SDK problems or learning API details.

---

### test_queries.sh
**Purpose**: Verify all KQL query examples work.

**What it tests**:
1. Recent logs query
2. Filter by environment
3. Extract nested fields (user_id, request.method, trace_id)
4. Query deeply nested values (level_3.deep_value)
5. Unpack attributes dynamically

**Use when**: Validating query examples from solution doc.

## Common Workflows

### Fresh Deployment
```bash
# 1. Deploy
cd log_LA/src/terraform
terraform apply -auto-approve

# 2. Ship logs
cd ..
python3 ship_logs.py

# 3. Wait 5 minutes, verify
./verify_logs.sh
```

### Resend Test Logs
```bash
cd log_LA/src
python3 ship_logs.py
# Wait 5 min, then: ./verify_logs.sh
```

### Check Logs in Azure Portal
```bash
# Get workspace ID
cd terraform
terraform output workspace_id

# Go to: portal.azure.com → Log Analytics workspaces
# → law-dcr-demo → Logs → Query:
# corplog_CL | where TimeGenerated > ago(24h)
```

### Cleanup
```bash
cd log_LA/src/terraform
terraform destroy -auto-approve
```

## Testing Scenarios

### Test 1: Flat Structure
**Code** (ship_logs.py:28-35):
```python
log_entry_1 = [{
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "level": 6,
    "message": "Test log entry - minimal flat structure",
    "host": "test-host-01",
    "environment": "dev"
}]
```

**Verify**: `./view_logs.sh` shows Log 1 with `attributes: null`

---

### Test 2: Nested Attributes
**Code** (ship_logs.py:37-63):
```python
log_entry_2 = [{
    "timestamp": datetime.now(timezone.utc).isoformat(),
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
}]
```

**Verify**: `./verify_logs.sh` shows nested JSON preserved, query:
```kql
corplog_CL
| extend deep_value = tostring(attributes.metadata.nested_object.level_3.deep_value)
| where deep_value == "test_deep_nesting"
```

---

### Test 3: Unknown Fields
**Code** (ship_logs.py:65-73):
```python
log_entry_3 = [{
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "level": 3,
    "message": "Test log entry - invalid with unexpected field",
    "host": "test-host-03",
    "environment": "prod",
    "unexpected_field": "This should cause the log to be dropped",
    "another_bad_field": 999
}]
```

**Verify**:
- Log appears in `corplog_CL` (SDK accepts it)
- `unexpected_field` and `another_bad_field` NOT in table (silently dropped)
- `./view_logs.sh` shows Log 3 with only standard fields

## Troubleshooting

### No Logs Appearing
```bash
# 1. Check DCR metrics
./diagnose.sh
# Look for: Total rows > 0

# 2. Search all tables
./find_logs.sh
# Confirms corplog_CL has data

# 3. Check ingestion lag
# Wait 10 minutes and retry
```

### Permission Denied (403)
```bash
# Grant yourself RBAC role
az role assignment create \
  --role "Monitoring Metrics Publisher" \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope $(cd terraform && terraform output -raw dcr_id)
```

### Table Not Found
```bash
# Verify table exists
./diagnose.sh
# Should show: ✓ Table 'corplog_CL' exists and is queryable

# If not, recreate table
cd terraform
terraform taint null_resource.create_custom_table
terraform apply
```

### Python Dependencies
```bash
# Reinstall
pip3 install --upgrade --force-reinstall -r requirements.txt

# Or use venv
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Key Files Content

### terraform/outputs.tf
```hcl
output "dcr_immutable_id" {
  value = azurerm_monitor_data_collection_rule.demo.immutable_id
}

output "dcr_ingestion_endpoint" {
  value = azurerm_monitor_data_collection_endpoint.demo.logs_ingestion_endpoint
}

output "stream_name" {
  value = "Custom-CorpLog"
}

output "workspace_id" {
  value = azurerm_log_analytics_workspace.demo.workspace_id
}
```

**Usage**: Python client reads these to configure SDK.

---

### ship_logs.py - Core Logic
```python
# Read Terraform outputs
dcr_id = subprocess.check_output(
    ["terraform", "output", "-raw", "dcr_immutable_id"],
    cwd="terraform"
).decode().strip()

# Authenticate
credential = DefaultAzureCredential()  # Uses az login

# Create client
client = LogsIngestionClient(
    endpoint=dcr_endpoint,
    credential=credential
)

# Upload logs
client.upload(
    rule_id=dcr_id,
    stream_name=stream_name,
    logs=[log_entry]
)
```

## Useful Commands

```bash
# Get workspace ID
cd terraform && terraform output -raw workspace_id

# Query via Azure CLI
az monitor log-analytics query \
  -w $(cd terraform && terraform output -raw workspace_id) \
  --analytics-query "corplog_CL | where TimeGenerated > ago(24h)" \
  -o table

# Check DCR details
az monitor data-collection rule show \
  --name dcr-corplog-demo \
  --resource-group rg-la-dcr-demo

# List all tables in workspace
az monitor log-analytics workspace table list \
  --workspace-name law-dcr-demo \
  --resource-group rg-la-dcr-demo \
  -o table

# Force Terraform refresh
cd terraform
terraform refresh
```

## Demo Script (5 minutes)

```bash
# Start fresh
cd log_LA/src

# 1. Show infrastructure (30s)
cd terraform && terraform output && cd ..

# 2. Send logs (10s)
python3 ship_logs.py
# Output: HTTP 204 x3

# 3. Wait indicator (2-5 min)
echo "Waiting for ingestion..."
sleep 120

# 4. Verify (30s)
./verify_logs.sh
# Shows: 3 logs with nested attributes

# 5. Detailed view (30s)
./view_logs.sh
# Shows: each log formatted with JSON

# 6. Query test (30s)
./test_queries.sh
# Validates: all KQL queries work
```

---

**Quick Links**:
- Terraform config: `log_LA/src/terraform/main.tf`
- Python client: `log_LA/src/ship_logs.py`
- Solution doc: `log_LA/documents/dcr_log_solution.md`
- Requirements: `log_LA/requirements/la_dcr.md`
