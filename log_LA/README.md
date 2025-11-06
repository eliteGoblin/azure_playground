# Azure Log Analytics DCR Ingestion Demo

This demo showcases custom log ingestion into Azure Log Analytics using Data Collection Rules (DCR) with a GELF-aligned schema.

## Architecture Overview

- **Custom Schema**: GELF-aligned with lowercase naming (except Azure defaults)
- **Table**: `corplog_cl` with columns: `level`, `message`, `host`, `environment`, `attributes` (dynamic)
- **Stream**: `Custom-CorpLog` for ingestion
- **Transform**: KQL-based validation that rejects unexpected root fields
- **Auth**: Managed Identity (no secrets)
- **Endpoint**: Public Direct DCR (no Private Link)

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.0
- Python >= 3.8
- Appropriate Azure subscription permissions to create resources

## Quick Start

### 1. Provision Infrastructure with Terraform

```bash
cd src/terraform

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# View outputs (DCR ID, ingestion URL, etc.)
terraform output
```

### 2. Install Python Dependencies

```bash
cd ../  # Back to src directory
python3 -m pip install -r requirements.txt
```

### 3. Run Verification Script

```bash
python3 verify_ingestion.py
```

The script sends three test cases:
1. **Valid flat log**: Required fields only (should be ingested)
2. **Valid nested log**: Includes multi-level `attributes` (should be ingested)
3. **Invalid log**: Contains unexpected root fields (should be DROPPED)

### 4. Verify in Azure Portal

Wait 2-5 minutes for ingestion, then:

**Query Log Analytics:**
```kql
corplog_cl
| where TimeGenerated > ago(10m)
| project TimeGenerated, level, message, host, environment, attributes
```

**Check nested attributes:**
```kql
corplog_cl
| where message contains "nested"
| project attributes
```

**Monitor DCR Metrics:**
- Navigate to the DCR resource in Azure Portal
- Check Metrics:
  - `RowsReceived` (should show 3)
  - `RowsDropped` (should show 1 for the invalid log)
  - `TransformationErrors` (may show 1)

## Log Schema

### Required Fields (top-level)
- `timestamp` (datetime, ISO-8601 UTC or epoch) → maps to `TimeGenerated`
- `level` (long, syslog 0-7)
- `message` (string)

### Recommended Fields (top-level)
- `host` (string)
- `environment` (string)

### Ad-hoc Fields
- `attributes` (dynamic) - supports nested objects/arrays at arbitrary depth

### Validation Rules
- Records with unexpected top-level fields (not in allowed list, not under `attributes`) are **rejected and dropped**
- Dropped records are visible in DCR metrics (`RowsDropped`, `TransformationErrors`)

## Terraform Outputs

| Output | Description |
|--------|-------------|
| `dcr_immutable_id` | DCR immutable ID for ingestion |
| `dcr_ingestion_endpoint` | Public ingestion endpoint URL |
| `stream_name` | Stream name (`Custom-CorpLog`) |
| `workspace_id` | Log Analytics workspace ID |
| `managed_identity_client_id` | Managed Identity client ID |

## Cleanup

To tear down all resources:

```bash
cd src/terraform
terraform destroy
```

## Troubleshooting

**No data appearing in Log Analytics:**
- Wait 2-5 minutes for ingestion pipeline
- Check DCR metrics for errors
- Verify Managed Identity has proper role assignment
- Check the DCR transform KQL for syntax errors

**Authentication errors:**
- Ensure `az login` is active
- Verify the Managed Identity has "Monitoring Metrics Publisher" role on the DCR
- Check that `DefaultAzureCredential` can acquire a token

**Invalid logs not being dropped:**
- Review the DCR transform KQL logic
- Check if field names match exactly (case-sensitive)
- Verify metrics are enabled on the DCR

## File Structure

```
log_LA/
├── README.md                    # This file
├── requirements/
│   ├── la_dcr.md               # Detailed requirements
│   └── original_raw.md         # Original requirement notes
└── src/
    ├── requirements.txt        # Python dependencies
    ├── verify_ingestion.py     # Verification script
    └── terraform/
        ├── .gitignore
        ├── main.tf             # Main infrastructure
        └── outputs.tf          # Terraform outputs
```
