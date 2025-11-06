# LA Retention & Export Verification

Verifies Azure Log Analytics retention options:
1. **Per-table retention**: 30 days hot + 365 days total (archive)
2. **Data export**: LA → Storage Account (continuous export)
3. **SA lifecycle policy**: 365-day retention enforcement

## Quick Start

### 1. Provision Infrastructure
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Verify outputs
terraform output
```

**Resources created**:
- Resource Group (`rg-la-retention-*`)
- Log Analytics Workspace (`law-retention-*`)
- Storage Account (`salogret*`) with lifecycle policy
- Data Collection Endpoint & Rule
- Custom Table (`TestExport_CL`) with 30/365 retention
- Data Export Rule (LA → SA)

---

### 2. Install Python Dependencies
```bash
pip3 install -r requirements.txt
```

---

### 3. Ship Test Logs
```bash
chmod +x ship_test_logs.py
python3 ship_test_logs.py
```

**What it does**:
- Sends 10 initial test logs
- Waits 5 seconds
- Sends 5 delta test logs (for export verification)
- Total: 15 logs with tracking IDs

**Expected output**:
```
✅ Successfully shipped 10 logs - HTTP 204
✅ Successfully shipped 5 logs - HTTP 204
```

---

### 4. Wait for Ingestion
```bash
# Wait 2-5 minutes for logs to appear in LA
sleep 180
```

---

### 5. Run Verification
```bash
chmod +x verify_retention.sh
./verify_retention.sh
```

**Checks performed**:
- ✅ Test 1: Table retention = 30 hot, 365 total
- ✅ Test 2: Export rule enabled for TestExport_CL
- ✅ Test 3: SA lifecycle policy = 365 days
- ✅ Test 4: Logs present in LA (count ≥10)
- ✅ Test 5: Exported blobs in SA container

**Expected output**:
```
✅ PASS: Table retention correctly set (30 hot + 335 archive)
✅ PASS: Export rule enabled and includes TestExport_CL
✅ PASS: Lifecycle policy set to delete after 365 days
✅ PASS: At least 10 logs found in LA table
✅ PASS: Export containers and blobs found
```

---

## Verification Details

### Table Retention Check
```bash
az monitor log-analytics workspace table show \
  --workspace-name <workspace> \
  --resource-group <rg> \
  --name TestExport_CL \
  --query '{retention:retentionInDays,totalRetention:totalRetentionInDays}'
```

**Expected**:
```json
{
  "retention": 30,
  "totalRetention": 365
}
```

**What it means**:
- Days 1-30: **Hot data** (fast queries, included in ingestion cost beyond day 31)
- Days 31-365: **Archive** (search jobs only, ~$0.02/GB/month)

---

### Export Rule Check
```bash
az monitor log-analytics workspace data-export show \
  --workspace-name <workspace> \
  --resource-group <rg> \
  --name <export-rule>
```

**Expected**:
```json
{
  "enabled": true,
  "tables": ["TestExport_CL"]
}
```

---

### Storage Account Blobs
Exported data lands in container named: `am-TestExport_CL`

**Blob path structure**:
```
am-TestExport_CL/
  WorkspaceResourceId=.../
    y=2025/
      m=01/
        d=06/
          h=14/
            m=00/
              PT05M.json  # 5-minute batch
```

**Download sample blob**:
```bash
SA_NAME=$(cd terraform && terraform output -raw storage_account_name)

az storage blob list \
  --account-name $SA_NAME \
  --container-name am-TestExport_CL \
  --auth-mode login \
  --query "[0].name" -o tsv

# Download first blob
az storage blob download \
  --account-name $SA_NAME \
  --container-name am-TestExport_CL \
  --name <blob-path> \
  --file sample.json \
  --auth-mode login

# Verify JSON Lines format
cat sample.json | jq -c '.[] | {TimeGenerated, message, test_id}'
```

---

## Cost Analysis

**Scenario**: 100 GB/day ingestion (3,000 GB/month steady state)

| Component | Option A: LA Only (30+365) | Option B: LA 30 + SA Export |
|-----------|---------------------------|---------------------------|
| LA Ingestion | $6,900 | $6,900 |
| LA Archive (335 days) | $3,350 | $0 |
| Export fee | $0 | $300 |
| SA storage (Cool, 365 days) | $0 | $365 |
| **Total/month** | **$10,250** | **$7,565** |
| **Savings** | - | **$2,685/month** |

**Recommendation**:
- **Analytics use case**: Use Option A (data stays in LA for queries)
- **Compliance-only**: Use Option B (cheaper, write-once-rarely-read)

---

## Cleanup

```bash
cd terraform
terraform destroy -auto-approve
```

Removes all resources (RG, LA workspace, SA, DCR, etc.).

---

## Troubleshooting

### No logs in LA after 5 minutes
```bash
# Check DCR metrics
cd terraform
RG=$(terraform output -raw resource_group_name)
DCR_NAME=$(az monitor data-collection rule list -g $RG --query "[0].name" -o tsv)

az monitor metrics list \
  --resource /subscriptions/.../resourceGroups/$RG/providers/Microsoft.Insights/dataCollectionRules/$DCR_NAME \
  --metric "Logs Rows Received" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
```

---

### No exported blobs in SA
**Possible reasons**:
1. Export has 5-10 min delay after ingestion
2. Export rule not enabled (check Test 2)
3. Logs haven't reached LA yet (check Test 4)

**Force check**:
```bash
SA_NAME=$(cd terraform && terraform output -raw storage_account_name)

# List all containers
az storage container list --account-name $SA_NAME --auth-mode login

# If container exists but empty, wait longer
# Export is near-realtime but can take up to 10 minutes
```

---

### Permission denied errors
```bash
# Grant yourself RBAC on DCR
cd terraform
DCR_ID=$(terraform output -raw dcr_immutable_id | cut -d'/' -f9)
RG=$(terraform output -raw resource_group_name)

az role assignment create \
  --role "Monitoring Metrics Publisher" \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.Insights/dataCollectionRules/$DCR_ID
```

---

## Files

```
src_LA_retention/
├── terraform/
│   ├── main.tf               # Infrastructure: RG, LA, SA, DCR, export rule
│   ├── outputs.tf            # DCR/LA/SA details
│   └── .gitignore            # Ignore tfstate files
├── ship_test_logs.py         # Send 15 test logs (10 initial + 5 delta)
├── verify_retention.sh       # Run all verification checks (PASS/FAIL)
├── requirements.txt          # Python dependencies
└── README.md                 # This file
```

---

## Success Criteria

All checks PASS:
- ✅ Table retention: 30 days hot + 365 days total
- ✅ Export rule: enabled and targeting TestExport_CL
- ✅ Lifecycle policy: 365-day retention in SA
- ✅ Logs ingested: ≥10 records in LA
- ✅ Blobs exported: Container `am-TestExport_CL` with JSON blobs

**Evidence saved**:
- Terraform state: `terraform/terraform.tfstate`
- Verification output: Run `./verify_retention.sh > verification-evidence.txt`
- Sample blob: Download and save as `sample-exported-log.json`

---

## References

- [LA Data Retention](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-retention-archive)
- [LA Data Export](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-data-export)
- [SA Lifecycle Policies](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-overview)
- [Requirements Doc](../requirements/la_retention_options.md)
