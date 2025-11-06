# Azure Logs Ingestion (DCR) Demo — Requirements (Terraform)

## Objective
Stand up a **minimal, working** demo to ingest custom app logs into **Log Analytics** via a **public (Direct) DCR**, using **Terraform only**. Keep schema **GELF-aligned**, **all-lowercase** (except Azure defaults), with a nested **`attributes`** JSON bucket for ad-hoc key/values.

---

## Scope (provision with Terraform)
- **Resource group**
  - Name: `rg-la-dcr-demo`
  - Region: `australiaeast`
- **Log Analytics Workspace**
  - Name: `law-dcr-demo`
- **Custom table (DCR-based)**
  - Name: `corplog_cl`
  - Columns (lowercase): `level: long`, `message: string`, `host: string`, `environment: string`, `attributes: dynamic`
  - Azure default: `TimeGenerated: datetime` (populated from `timestamp`)
- **Data Collection Rule (Direct/public)**
  - Name: `dcr-corplog-demo`
  - **Stream** `Custom-CorpLog` (incoming): `timestamp: datetime`, `level: long`, `message: string`, `host: string`, `environment: string`, `attributes: dynamic`
  - **Data flow**: `Custom-CorpLog` → `corplog_cl`
  - **Transform (KQL)**:
    - Map `timestamp` → `TimeGenerated`
    - Coerce required types
    - Pass through `attributes` (dynamic)
    - **Reject** any record with **unexpected top-level fields** (not in the list above and not under `attributes`) so “invalid” logs are **dropped** and observable in metrics
- **Managed Identity (User-Assigned)**
  - Name: `uami-dcr-demo`
  - Role on the **DCR**: **Monitoring Metrics Publisher**
- **Diagnostics / Metrics**
  - Enable visibility for **RowsReceived**, **RowsDropped**, **TransformationErrors**
- **Terraform Outputs**
  - DCR **immutable ID**
  - DCR **ingestion URL** (Direct/public)
  - **Stream name**
  - LA workspace **resource ID / workspace ID**

---

## Log schema (GELF-aligned, lowercase)
- **Required (top-level)**: `timestamp` (ISO-8601 UTC or epoch seconds) → `TimeGenerated`, `level` (integer syslog 0–7), `message` (string)
- **Recommended (top-level)**: `host` (string), `environment` (string)
- **Ad-hoc fields**: `attributes` (dynamic JSON; supports nested objects/arrays; arbitrary depth)

---

## Authentication & Networking
- **Auth**: Managed Identity only (no secrets)
- **Endpoint**: public **Direct DCR** ingestion (no DCE/Private Link)
- **Token handling**: client uses standard SDK token acquisition (no manual tokens)

---

## Client verification (Python SDK)
- Use **Azure Monitor Logs Ingestion** Python SDK with `DefaultAzureCredential` (MI) to send:
  1) **Valid minimal (flat)**: `timestamp`, `level`, `message` (optional `host`, `environment`), **no `attributes`**
  2) **Valid nested**: includes `attributes` with nested KVs (multi-level)
  3) **Invalid**: includes an **unexpected root** field (not allowed, not under `attributes`) → expect **row dropped**
- **Verify** in LA & DCR metrics/logs:
  - Cases **1 & 2** appear in `corplog_cl`
  - Case **3** is **not** ingested; **RowsDropped**/**TransformationErrors** increment
  - `attributes` nested values are queryable

---

## Naming & conventions
- All custom columns **lowercase**; Azure’s `TimeGenerated` unchanged
- Resource names fixed as listed; region fixed to `australiaeast`

---

## DCR mental model (concise)
- **Table**: where rows land (defined columns + `TimeGenerated`)
- **Stream**: **ingress contract** (names/types) for posted payloads
- **Data flow + Transform**: **on-the-fly processing** from stream → table (map time, cast types, validate/allow/drop)

---

## Constraints / non-goals
- **Terraform only** (no Bicep/ARM/CLI for provisioning)
- No Private Link/DCE for this demo
- Only resources required to ingest, observe, and query

---

## Acceptance criteria
- All resources provisioned via **Terraform** and **idempotent**
- Direct DCR ingestion works using MI-based Python client
- Valid logs (flat/nested) appear in `corplog_cl` promptly
- Invalid logs (unexpected root fields) are **dropped**; drops visible in metrics/logs
- `attributes` supports nested JSON without schema changes
- Terraform outputs expose DCR immutable ID, ingestion URL, and stream name
- Generate code in log_LA/src, terraform code in log_LA/terraform


# Document Generate

Generate a solution document in log_LA/documents/dcr_log_solution.md

* Illustrating the demo solution
* Create a section about auth: although demo use terminal's already loggined in Azure session (do not mention it), mention in corp implementation: we can assign UAMI into VM, and VM itself can ship log into LA/DCR
* Generate diagram: illustrating log data lifecycle and compoenent it passing through, explain core compoenent like stream(source?), DCR (schema and optional KQL to transform), and table as destination. 
* Show the example code, and data got from Azure. like the JSON data. Show the Python testing data how it send into DCR, and what's data inside (you can mention result from the verify script), like showing the 3 logs to illustrate 3 diffrerent scenario: especially with nested fields and with unknow fields. 
* I want this document as solution doc, for team to understand the solution, with example code and data from this solution. as evidence. 
* Make it less verbose like AI generated. make it core, concise, avoid putting "fancy words" which have low info density. explain core idea, with example help reader to build mental model and understand. 

Note:
* I also had another sesison with GPT, result GPT generated doc log_LA/documents/gpt_solution.md, refer to it as well, mainly section of different scenario: when VM, AKS, MDP, and OSS(like fluentbit) how it can ship log into DCR. 
* Core use case here is we ship custom log directly into DCR into predefined table, which you use the solution you built as source of truth for this. just use GPT generated one as reference, enrichment


# Ignore below requirement

Ignore requirement in this section and below

## Provision a ServicePrinciple which has access to ship log into LA/DCR

* Provision SP, which contain minimum permission to able to ship log into LA/DCR
* Verify Python code can "assume" this SP and ship log into LA/DCR, and you also need to verify it's there. i.e e2e working
* Get password from tf state if need, seems to me SP credential should stored in TF state as plaintext, or whatever how you did it, I want you create a SP for demo and you able to fetch its secret

## Auto pack DCR

* In corp, I want a more flexible DCR: it can auto map unknown fields in root level all into a dynamic attributes col. i.e If not core "GELF" fields, it will be converted automatically into attributes, "pack". 
* If required fields missed, make it align with default DCR behaviour, reject or accept all ok, explain to me the default behaviour if required "MY GELF" fields missing

## Private endpoint explore

* Corp need PE to ship log, so need to verify the solution to via a private endpoint 
* Need to provision some Azure resource which via PE to ship log into DCR
