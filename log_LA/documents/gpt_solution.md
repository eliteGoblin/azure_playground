Azure Custom Log Ingestion (DCR) — Solution Document (for Claude)
1) Goals


Ingest custom application logs to Log Analytics (LA) using a public (Direct) DCR.


Keep schema GELF-aligned, lowercase (except Azure defaults), with nested attributes for ad-hoc KVs.


Provision everything via Terraform (no other IaC).


Provide a Python SDK demo client to send and verify logs.


Map the broader logging picture for VMs, AKS, OSS shippers, and MDP.



2) Target Schema (GELF-aligned, lowercase)
Required top-level fields:


timestamp (ISO-8601 UTC or epoch seconds) → mapped to Azure’s TimeGenerated.


level (integer, syslog 0–7).


message (string).


Recommended top-level fields:


host (string), environment (string).


Ad-hoc fields:


attributes (dynamic JSON; can contain nested objects/arrays, arbitrary depth).


Example payload (conceptual):
{ "timestamp": "2025-11-05T06:40:00Z", "level": 6, "message": "deploy started", "host": "aks-node-07", "environment": "prod", "attributes": { "http": { "path": "/v1/health", "status": 200, "latency_ms": 123 }, "trace": { "trace_id": "abc" } } }

3) Mental Model (DCR pieces)


LA workspace = the database.


Table (e.g., corplog_cl) = where rows live (defined columns plus Azure’s TimeGenerated).


DCR = traffic cop: declares streams (ingress contracts) and data flows (routing to tables) with optional transform KQL (reshape/cast/validate).


Flow: client (app/shipper) → Stream (DCR) → Transform (KQL) → Destination table (LA).



4) Provisioning (Terraform only)
Provision the following (no code here—Claude should implement in Terraform):


RG: rg-la-dcr-demo (region australiaeast).


Log Analytics Workspace: law-dcr-demo.


Custom table (DCR-based): corplog_cl with columns: level: long, message: string, host: string, environment: string, attributes: dynamic (Azure keeps TimeGenerated).


DCR (Direct/public): dcr-corplog-demo.


Stream: Custom-CorpLog (incoming fields: timestamp: datetime, level: long, message: string, host: string, environment: string, attributes: dynamic).


Data flow: Custom-CorpLog → corplog_cl.


Transform KQL (authoritative behavior):


Map timestamp to TimeGenerated using TimeGenerated = todatetime(column_ifexists("timestamp", now())).


Coerce types: level = tolong(level), message = tostring(message), etc.


Ensure attributes = todynamic(column_ifexists("attributes", dynamic({}))).


Policy for invalid rows: if unexpected root keys are present (not in the known list and not under attributes), drop the record so drops are observable in DCR metrics.


Project only: TimeGenerated, level, message, host, environment, attributes.






Managed Identity (UAMI): uami-dcr-demo, assigned Monitoring Metrics Publisher on the DCR.


Diagnostics/metrics: enable to observe RowsReceived, RowsDropped, TransformationErrors.


Terraform outputs: DCR immutable ID, DCR ingestion URL, stream name, LA workspace IDs.



5) Python SDK Client (for verification)


Auth: use DefaultAzureCredential; for MI, run on an Azure resource with the UAMI attached; for local quick test, rely on az login.


Library: Azure Monitor Logs Ingestion client.


Inputs: DCR ingestion URL, DCR immutable ID, stream name.


Send three cases:


Valid minimal (flat): timestamp, level, message (optional host, environment), no attributes.


Valid nested: include attributes with nested KVs/arrays.


Invalid: add an unexpected root field (e.g., branch: "main") outside attributes → expect drop.




Verify in LA:


Query recent rows: corplog_cl | where TimeGenerated > ago(1h) | order by TimeGenerated desc.


Peek nested data: corplog_cl | extend path = tostring(attributes.http.path) | take 20.


Confirm drops via DCR metrics (RowsDropped / TransformationErrors) and, if enabled, DCR diagnostic logs.





6) Other Logging Scenarios (enterprise view)
A) Azure VMs & on-prem servers


Azure Monitor Agent (AMA) + DCR (recommended):


Associate a DCR to each VM/Arc server to collect Windows Events, Syslog, and Custom Text Logs.


No app changes; file tailing lands in LA (you can route/transform with DCR).




OSS shipper alternative (where standardised):


Fluent Bit with the Azure Logs Ingestion output → DCE + DCR (Private Link capable).


Good for multi-sink routing or existing Fluent Bit estates.




B) AKS (container stdout/stderr)


Container insights (Azure Monitor for containers):


Deployed AMA on nodes ships stdout/stderr into ContainerLogV2 in LA; apply DCR transforms to shape/filter.


Use your app→DCR pattern only when you need a strict custom schema separate from ContainerLogV2.




OSS in-cluster alternative: Fluent Bit DaemonSet → DCE + DCR.


C) Azure DevOps (ADO) & Managed DevOps Pools (MDP)


ADO audit logs: native streaming to Log Analytics for compliance.


Pipeline logs:


No single switch to LA; use a pipeline step (Python/PowerShell) posting to Logs Ingestion API (DCR), or tail agent files with Fluent Bit → DCE + DCR.




MDP diagnostics:


Confirmed via your screenshot: MDP supports Diagnostic settings to Log Analytics (e.g., “Resource Provisioning Logs” → LA).


You can still add Storage/Event Hub if you want a parallel landing zone or replay pipeline.




D) Azure resource/platform logs


Use each resource’s Diagnostic settings → Log Analytics (separate from AMA/DCR). Typical for Key Vault, Storage, Firewalls, etc.



7) Compliance & Network Isolation


Public demo: Direct DCR ingestion endpoint is fine.


Corp/gov isolation: front ingestion and workspace access with DCE + AMPLS (Azure Monitor Private Link Scope); ship logs privately over Private Link; client still targets DCR (now via DCE).



8) Acceptance Criteria (end-to-end)


Terraform deploys RG, LAW, table, DCR (Direct), UAMI, diagnostics, and outputs (idempotent).


Python SDK client (MI) successfully ingests valid minimal + nested logs; invalid root fields are dropped and visible in DCR metrics.


Table queries return expected rows; nested attributes are queryable without schema updates.


Additional pathways validated where applicable:


AMA+DCR for VM/Arc file logs.


Container insights for AKS stdout/stderr.


ADO audit to LA; pipeline step posts to DCR.


MDP diagnostics to LA (per portal capability shown).





9) Quick Operator Queries (helpful snippets)


Recent rows: corplog_cl | where TimeGenerated > ago(24h) | order by TimeGenerated desc | take 200.


Attributes exploration: corplog_cl | evaluate bag_unpack(attributes) | take 200.


Filter by environment: corplog_cl | where environment == "prod" | summarize count() by level.


Container logs check (AKS): ContainerLogV2 | where TimeGenerated > ago(1h) | take 50.



10) Notes for Claude (implementation guidance)


Use Terraform providers azurerm (for RG/LAW/Identity/Role) and, where needed, azapi (for LA table & DCR modeling if AzureRM coverage is partial).


Keep column names lowercase (Azure’s TimeGenerated remains).


Output the exact DCR ingestion URL, stream name, and immutable ID for the Python client.


Prefer Managed Identity everywhere (no secrets); assign Monitoring Metrics Publisher on the DCR.


Enable metrics/diagnostic logs on the DCR so dropped rows and transform errors are observable.



