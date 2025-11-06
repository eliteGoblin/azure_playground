# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Azure Log Analytics ingestion demo using Data Collection Rules (DCR). The project demonstrates custom log ingestion into Azure Log Analytics via public DCR endpoints using Terraform for infrastructure provisioning and Python for client verification.

## Architecture

### Log Schema (GELF-aligned)
- **Top-level required fields**: `timestamp` (ISO-8601 UTC or epoch) → maps to `TimeGenerated`, `level` (integer syslog 0-7), `message` (string)
- **Top-level recommended fields**: `host` (string), `environment` (string)
- **Ad-hoc fields**: `attributes` (dynamic JSON bucket supporting nested objects/arrays at arbitrary depth)
- **Naming convention**: All custom columns lowercase; Azure defaults like `TimeGenerated` unchanged

### DCR Mental Model
- **Table** (`corplog_cl`): Final destination with defined columns + `TimeGenerated`
- **Stream** (`Custom-CorpLog`): Ingress contract defining expected payload structure
- **Transform (KQL)**: Maps `timestamp` → `TimeGenerated`, coerces types, validates schema, **rejects records with unexpected top-level fields** (not in allowed list and not under `attributes`)

### Infrastructure Components
- **Resource Group**: `rg-la-dcr-demo` (australiaeast)
- **Log Analytics Workspace**: `law-dcr-demo`
- **Custom Table**: `corplog_cl` with columns: `level: long`, `message: string`, `host: string`, `environment: string`, `attributes: dynamic`
- **DCR**: `dcr-corplog-demo` (public/Direct, no Private Link)
- **Managed Identity**: `uami-dcr-demo` with Monitoring Metrics Publisher role on DCR
- **Diagnostics**: Enabled for RowsReceived, RowsDropped, TransformationErrors metrics

## Development Commands

### Terraform
```bash
cd log_LA/src/terraform
az login                    # Authenticate to Azure
terraform init              # Initialize Terraform
terraform plan              # Preview changes
terraform apply             # Provision infrastructure
terraform output            # View DCR immutable ID, ingestion URL, stream name, workspace ID
terraform destroy           # Tear down demo
```

### Python Client (verification)
Expected to use Azure Monitor Logs Ingestion SDK with `DefaultAzureCredential` (Managed Identity) to send test cases:
1. Valid minimal (flat): required fields only, no `attributes`
2. Valid nested: includes `attributes` with multi-level nested key-values
3. Invalid: includes unexpected root field → should be dropped, observable in DCR metrics

## Key Constraints
- **Terraform only** for provisioning (no Bicep/ARM/CLI)
- **Managed Identity auth only** (no secrets/tokens)
- **Public DCR endpoint** (no DCE/Private Link)
- **Region fixed**: australiaeast
- **Schema validation**: Unexpected top-level fields are rejected and dropped (visible in metrics)

## Generated Code Locations
- Terraform: `log_LA/src/terraform/`
- Python clients: `log_LA/src/` (root or subdirectory)
- Requirements docs: `log_LA/requirements/`
