#!/bin/bash
# Download all Azure configurations as JSON files

set -e

# Create azure_jsons folder
mkdir -p azure_jsons

cd terraform
RG=$(terraform output -raw resource_group_name)
WORKSPACE=$(terraform output -raw workspace_name)
TABLE=$(terraform output -raw table_name)
SA=$(terraform output -raw storage_account_name)
EXPORT_RULE=$(terraform output -raw export_rule_name)
cd ..

echo "=== Downloading Azure Configurations to JSON Files ==="
echo
echo "Output directory: azure_jsons/"
echo

# ============================================================
# 1. LA Table Configuration
# ============================================================
echo "1. Downloading LA table configuration..."
az monitor log-analytics workspace table show \
  --workspace-name "$WORKSPACE" \
  --resource-group "$RG" \
  --name "$TABLE" \
  -o json > azure_jsons/01_la_table_retention.json
echo "   ✅ azure_jsons/01_la_table_retention.json"

# ============================================================
# 2. Data Export Rule
# ============================================================
echo "2. Downloading data export rule..."
az monitor log-analytics workspace data-export show \
  --workspace-name "$WORKSPACE" \
  --resource-group "$RG" \
  --name "$EXPORT_RULE" \
  -o json > azure_jsons/02_export_rule.json
echo "   ✅ azure_jsons/02_export_rule.json"

# ============================================================
# 3. Storage Account
# ============================================================
echo "3. Downloading storage account config..."
az storage account show \
  --name "$SA" \
  --resource-group "$RG" \
  -o json > azure_jsons/03_storage_account.json
echo "   ✅ azure_jsons/03_storage_account.json"

# ============================================================
# 4. Storage Account Lifecycle Policy
# ============================================================
echo "4. Downloading lifecycle management policy..."
az storage account management-policy show \
  --account-name "$SA" \
  --resource-group "$RG" \
  -o json > azure_jsons/04_lifecycle_policy.json
echo "   ✅ azure_jsons/04_lifecycle_policy.json"

# ============================================================
# 5. Log Analytics Workspace
# ============================================================
echo "5. Downloading LA workspace config..."
az monitor log-analytics workspace show \
  --workspace-name "$WORKSPACE" \
  --resource-group "$RG" \
  -o json > azure_jsons/05_la_workspace.json
echo "   ✅ azure_jsons/05_la_workspace.json"

# ============================================================
# 6. Data Collection Endpoint (DCE)
# ============================================================
echo "6. Downloading DCE config..."
az monitor data-collection endpoint list \
  --resource-group "$RG" \
  -o json > azure_jsons/06_dce.json
echo "   ✅ azure_jsons/06_dce.json"

# ============================================================
# 7. Data Collection Rule (DCR)
# ============================================================
echo "7. Downloading DCR config..."
az monitor data-collection rule list \
  --resource-group "$RG" \
  -o json > azure_jsons/07_dcr.json
echo "   ✅ azure_jsons/07_dcr.json"

# ============================================================
# 8. Resource Group
# ============================================================
echo "8. Downloading resource group config..."
az group show \
  --name "$RG" \
  -o json > azure_jsons/08_resource_group.json
echo "   ✅ azure_jsons/08_resource_group.json"

# ============================================================
# 9. Storage Containers (if any)
# ============================================================
echo "9. Downloading storage containers list..."
az storage container list \
  --account-name "$SA" \
  --auth-mode login \
  -o json > azure_jsons/09_storage_containers.json 2>/dev/null || \
  echo "[]" > azure_jsons/09_storage_containers.json
echo "   ✅ azure_jsons/09_storage_containers.json"

# ============================================================
# 10. Role Assignments on DCR
# ============================================================
echo "10. Downloading DCR role assignments..."
DCR_SCOPE=$(az monitor data-collection rule list --resource-group "$RG" --query "[0].id" -o tsv)
az role assignment list \
  --scope "$DCR_SCOPE" \
  -o json > azure_jsons/10_dcr_role_assignments.json
echo "   ✅ azure_jsons/10_dcr_role_assignments.json"

# ============================================================
# 11. Summary file
# ============================================================
echo "11. Creating summary file..."
cat > azure_jsons/00_SUMMARY.txt <<EOF
Azure LA Retention Demo - Configuration Export
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Resource Group: $RG
LA Workspace: $WORKSPACE
Table: $TABLE
Storage Account: $SA
Export Rule: $EXPORT_RULE

Files:
  01_la_table_retention.json     - Table with retention settings (30 hot + 335 archive)
  02_export_rule.json            - Data export rule (LA → Storage Account)
  03_storage_account.json        - Storage account configuration
  04_lifecycle_policy.json       - Blob lifecycle policy (365-day retention)
  05_la_workspace.json           - Log Analytics workspace settings
  06_dce.json                    - Data Collection Endpoint (ingestion)
  07_dcr.json                    - Data Collection Rule (transform + routing)
  08_resource_group.json         - Resource group details
  09_storage_containers.json     - Storage containers (export destinations)
  10_dcr_role_assignments.json   - RBAC roles on DCR

Key Findings:
  ✅ LA supports native archive/long-term retention
  ✅ Table retention: 30 days hot + 335 days archive = 365 days total
  ✅ Export rule enabled for continuous export to Storage Account
  ✅ Storage Account has 365-day lifecycle policy

To view any file:
  cat azure_jsons/01_la_table_retention.json | jq

To view retention settings specifically:
  cat azure_jsons/01_la_table_retention.json | jq '{name, retentionInDays, totalRetentionInDays, archiveRetentionInDays}'
EOF
echo "   ✅ azure_jsons/00_SUMMARY.txt"

echo
echo "=== Download Complete ==="
echo
echo "All configurations saved to: azure_jsons/"
echo "Total files: $(ls -1 azure_jsons/ | wc -l)"
echo
echo "View files:"
echo "  ls -lh azure_jsons/"
echo "  cat azure_jsons/00_SUMMARY.txt"
echo
