# Azure Log Analytics: Long-term Retention Solutions

## Problem Statement

Corporate default: 30-day Log Analytics retention. Requirement: 365-day retention for compliance.

**Question**: Does Azure LA support cost-effective long-term retention?

**Answer**: Yes. Two options:
1. **LA Native Archive** (30 hot + 335 archive = 365 total)
2. **Export to Storage Account** (continuous export + lifecycle policy)

---

## Option A: LA Native Archive Retention

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Log Analytics Table: testexport_CL                         │
│                                                              │
│  Day 0-30:  Hot Tier (Analytics)                           │
│             ├─ Fast queries (seconds)                       │
│             ├─ $2.76/GB/month ingestion                     │
│             └─ Immediate access                             │
│                                                              │
│  Day 31-365: Archive Tier                                   │
│             ├─ Slower queries (minutes)                     │
│             ├─ $0.26/GB/month storage (~90% cheaper)        │
│             ├─ Must restore to query                        │
│             └─ Auto-transition from hot                     │
│                                                              │
│  Day 365+:  Auto-deleted                                    │
└──────────────────────────────────────────────────────────────┘
```

### Actual Configuration (from deployed Azure)

**Table retention settings** (`azure_jsons/01_la_table_retention.json`):

```json
{
  "name": "testexport_CL",
  "plan": "Analytics",
  "retentionInDays": 30,
  "totalRetentionInDays": 365,
  "archiveRetentionInDays": 335,
  "provisioningState": "Succeeded"
}
```

**Key fields**:
- `plan: "Analytics"` - Required for archive support (Basic plan doesn't support archive)
- `retentionInDays: 30` - Hot tier duration (fast queries)
- `totalRetentionInDays: 365` - Total retention period
- `archiveRetentionInDays: 335` - Auto-calculated (365 - 30)

### Terraform Implementation

```hcl
# Create table with retention via Azure CLI (azurerm provider doesn't support retention yet)
resource "null_resource" "create_test_table" {
  provisioner "local-exec" {
    command = <<-EOT
      az monitor log-analytics workspace table create \
        --resource-group ${azurerm_resource_group.retention_demo.name} \
        --workspace-name ${azurerm_log_analytics_workspace.retention_demo.name} \
        --name testexport_CL \
        --retention-time 30 \
        --total-retention-time 365 \
        --plan Analytics \
        --columns TimeGenerated=datetime level=long message=string test_id=string sequence=long
    EOT
  }
}
```

### Querying Archive Data

```kql
// Query hot data (Day 0-30) - instant results
testexport_CL
| where TimeGenerated > ago(30d)
| summarize count() by bin(TimeGenerated, 1d)

// Query archive data (Day 31-365) - requires restore job
testexport_CL
| where TimeGenerated between (ago(365d) .. ago(31d))
| summarize count() by bin(TimeGenerated, 1d)
// Note: First query triggers async restore job (~5 min), subsequent queries are fast
```

### Cost Breakdown (100GB/day workload)

| Component | Storage | Monthly Cost |
|-----------|---------|--------------|
| Hot tier (30 days × 100GB) | 3TB | $2.76/GB ingestion + $0.10/GB storage = ~$288/month |
| Archive tier (335 days × 100GB) | 33.5TB | $0.026/GB storage = ~$871/month |
| **Total** | 36.5TB | **$1,159/month** |

**If all data kept hot**: 36.5TB × $0.10/GB = $3,650/month
**Savings**: $2,491/month (68% reduction)

---

## Option B: Export to Storage Account

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Log Analytics Table: testexport_CL                            │
│                                                                 │
│  Day 0-30:  Hot Tier Only                                      │
│             └─ 30 days retention, then deleted from LA         │
│                       │                                         │
│                       │ (Continuous Export)                     │
│                       ▼                                         │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Storage Account: salogretvewcvs                        │  │
│  │  Container: am-testexport_CL/                           │  │
│  │                                                          │  │
│  │  Day 0-365: Cool Tier                                   │  │
│  │             ├─ Immutable JSON blobs                     │  │
│  │             ├─ $0.01/GB/month storage                   │  │
│  │             ├─ Query via Azure Data Explorer            │  │
│  │             └─ Lifecycle policy deletes after 365 days  │  │
│  │                                                          │  │
│  │  Day 365+:  Auto-deleted by lifecycle policy           │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Actual Configuration

**Export rule** (`azure_jsons/02_export_rule.json`):

```json
{
  "name": "export-testexport-vewcvs",
  "enable": true,
  "tableNames": ["testexport_CL"],
  "destination": {
    "resourceId": "/subscriptions/.../storageAccounts/salogretvewcvs",
    "type": "StorageAccount"
  },
  "createdDate": "2025-11-06T05:33:04Z"
}
```

**Lifecycle policy** (`azure_jsons/04_lifecycle_policy.json`):

```json
{
  "name": "DefaultManagementPolicy",
  "policy": {
    "rules": [
      {
        "name": "delete-after-365-days",
        "enabled": true,
        "definition": {
          "filters": {
            "blobTypes": ["blockBlob"],
            "prefixMatch": ["am-"]
          },
          "actions": {
            "baseBlob": {
              "delete": {
                "daysAfterCreationGreaterThan": 365.0
              }
            }
          }
        }
      }
    ]
  }
}
```

**Key observations**:
- `enable: true` - Export is active
- `prefixMatch: ["am-"]` - LA exports use "am-" prefix (Analytics Model)
- `daysAfterCreationGreaterThan: 365.0` - Auto-delete after 365 days

### Terraform Implementation

```hcl
# Storage Account with Cool tier
resource "azurerm_storage_account" "logs" {
  name                     = "salogret${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.retention_demo.name
  location                 = azurerm_resource_group.retention_demo.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Cool"  # $0.01/GB vs $0.02/GB hot
}

# Lifecycle policy
resource "azurerm_storage_management_policy" "retention_policy" {
  storage_account_id = azurerm_storage_account.logs.id

  rule {
    name    = "delete-after-365-days"
    enabled = true
    filters {
      prefix_match = ["am-"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = 365
      }
    }
  }
}

# Export rule (requires Azure CLI - not in azurerm provider yet)
resource "null_resource" "create_export_rule" {
  provisioner "local-exec" {
    command = <<-EOT
      az monitor log-analytics workspace data-export create \
        --resource-group ${azurerm_resource_group.retention_demo.name} \
        --workspace-name ${azurerm_log_analytics_workspace.retention_demo.name} \
        --name export-${var.table_name} \
        --tables ${var.table_name} \
        --destination ${azurerm_storage_account.logs.id}
    EOT
  }
}
```

### Querying Exported Data

Exported blobs are JSON format in path: `am-<tablename>/WorkspaceResourceId=<workspace-id>/y=<year>/m=<month>/d=<day>/h=<hour>/m=<minute>/PT1H.json`

**Query via Azure Data Explorer**:
```kql
// Mount external table from Storage Account
.create external table ExportedLogs (
    TimeGenerated: datetime,
    level: long,
    message: string,
    test_id: string
)
kind=blob
dataformat=json
(
    h@'https://salogretvewcvs.blob.core.windows.net/am-testexport_CL'
)

// Query exported data
ExportedLogs
| where TimeGenerated > ago(365d)
| summarize count() by bin(TimeGenerated, 1d)
```

### Cost Breakdown (100GB/day workload)

| Component | Storage | Monthly Cost |
|-----------|---------|--------------|
| LA hot tier (30 days × 100GB) | 3TB | $2.76/GB ingestion + $0.10/GB storage = ~$288/month |
| Storage Account Cool tier (365 days × 100GB) | 36.5TB | $0.01/GB storage = ~$365/month |
| **Total** | 36.5TB | **$653/month** |

**Savings vs Option A**: $506/month (44% cheaper)
**Savings vs all-hot LA**: $2,997/month (82% cheaper)

---

## Cost Comparison (100GB/day workload)

| Solution | Hot Storage | Archive Storage | Monthly Cost |
|----------|-------------|-----------------|--------------|
| **All-hot LA** (baseline) | 36.5TB (365 days) | 0TB | $3,650 |
| **Option A: LA Archive** | 3TB (30 days) | 33.5TB (335 days) | $1,159 (68% cheaper) |
| **Option B: SA Export** | 3TB (30 days) | 36.5TB (365 days) | $653 (82% cheaper) |

---

## Verification Commands

### Check table retention settings
```bash
az monitor log-analytics workspace table show \
  --workspace-name law-retention-xxxxx \
  --resource-group rg-la-retention-xxxxx \
  --name testexport_CL \
  --query '{retention:retentionInDays,total:totalRetentionInDays,archive:archiveRetentionInDays}'

# Output:
# {
#   "archive": 335,
#   "retention": 30,
#   "total": 365
# }
```

### Check export rule status
```bash
az monitor log-analytics workspace data-export show \
  --workspace-name law-retention-xxxxx \
  --resource-group rg-la-retention-xxxxx \
  --name export-testexport-xxxxx \
  --query '{enabled:enable,tables:tableNames,destination:destination.resourceId}'

# Output:
# {
#   "destination": "/subscriptions/.../storageAccounts/salogretvewcvs",
#   "enabled": true,
#   "tables": ["testexport_CL"]
# }
```

### Check lifecycle policy
```bash
az storage account management-policy show \
  --account-name salogretvewcvs \
  --resource-group rg-la-retention-xxxxx \
  --query 'policy.rules[0].{name:name,enabled:enabled,deleteAfterDays:definition.actions.baseBlob.delete.daysAfterCreationGreaterThan}'

# Output:
# {
#   "deleteAfterDays": 365.0,
#   "enabled": true,
#   "name": "delete-after-365-days"
# }
```

---

## Decision Matrix: Which Option to Use?

| Scenario | Recommended Option | Reason |
|----------|-------------------|---------|
| Occasional archive queries (monthly audits) | **Option A: LA Archive** | Query in LA portal without external tools |
| Frequent archive queries (daily analytics) | **Option B: SA Export** | Cheaper storage + ADX for fast queries |
| Compliance/immutability required | **Option B: SA Export** | Blob immutability policies available |
| Minimal operational overhead | **Option A: LA Archive** | Single system, no external dependencies |
| Maximum cost savings | **Option B: SA Export** | 44% cheaper than Option A |
| Multi-region replication | **Option B: SA Export** | Storage Account supports GRS/GZRS |

---

## Key Findings

1. **Azure LA DOES support native cold retention** via Archive tier
   - Requires `plan: "Analytics"` (not Basic)
   - Auto-transitions after `retentionInDays` expires
   - 90% cheaper than hot tier ($0.026/GB vs $0.10/GB)

2. **Export to Storage Account is cheaper** but requires external query tools
   - 82% cheaper than all-hot LA
   - 44% cheaper than LA Archive option
   - Requires Azure Data Explorer or custom tooling for queries

3. **Both options proven functional** in deployed demo environment
   - See `src_LA_retention/azure_jsons/` for full JSON configs
   - Run `src_LA_retention/verify_retention.sh` to validate

---

## References

**Demo Source**: `log_LA/src_LA_retention/`

**Configuration Exports**: `log_LA/src_LA_retention/azure_jsons/`
- `01_la_table_retention.json` - Archive retention proof
- `02_export_rule.json` - Export configuration
- `04_lifecycle_policy.json` - Storage lifecycle policy

**Verification Scripts**:
- `verify_retention.sh` - Automated checks for all settings
- `show_configs.sh` - Display JSON configs with explanations
- `download_configs.sh` - Export all configs to `azure_jsons/`

**Terraform**: `log_LA/src_LA_retention/terraform/`

**Azure Pricing** (Australia East, as of 2025):
- LA ingestion: $2.76/GB
- LA storage (hot): $0.10/GB/month
- LA storage (archive): $0.026/GB/month
- Storage Account (cool): $0.01/GB/month
- Archive restore: $0.02/GB (one-time per restore job)
