Azure Log Analytics Retention & Export — Verification Requirements (KISS)
0) Scope & Goal

Prove from scratch that:

Per-table retention in Log Analytics (LA) can be set to 30 days Analytics and 365 days Total (i.e., with LA long-term retention, no Storage Account).

Table-based Data Export from LA to a Storage Account (SA) works, and the SA enforces 365-day retention (lifecycle policy or immutability).

Record machine-checkable evidence for each step.

Use Terraform first. Fall back to CLI/REST only if the provider lacks a specific resource.

Note:

* Create all code in src_LA_retention folder, put terraform code in terraform/ folder
* Create dependency if need for this demo. keep this sepaerate. do not rely on existing azure resources

1) Fresh Test Environment

RG: Create a new resource group (unique name/region).

LA: Create one Log Analytics workspace (same region as SA).

SA: Create one GPv2 Storage Account (same region as LA).

Create a management lifecycle policy (or immutability/WORM) to keep blobs ≥365 days.

2) Test Table & Sample Data

Table: Ensure a test table exists (prefer a custom DCR-based table, e.g., TestExport_CL).

Ingest: Insert ≥10 records (Logs Ingestion API with DCE+DCR or generate activity logs).

Verify arrival: Simple count query shows new rows in the table.

3) LA Per-Table Retention (no SA)

Set Analytics retention = 30 days on the test table.

Set Total retention = 365 days on the test table.

Verify via API/CLI: read table properties and assert:

retentionInDays == 30

totalRetentionInDays == 365

4) LA → SA Continuous Export (table-based)

Create one Data Export rule that includes the test table and targets the SA.

Respect constraints: same region, supported SA SKU.

Delta test: After enabling export, ingest ≥5 new records.

Verify in SA:

A per-table container (e.g., am-TestExport_CL) exists.

JSON Lines blobs appear in time-partitioned folders and contain the new records.

5) SA Retention (365 days)

Lifecycle policy: tier/delete ≥365-day blobs or

Immutability (WORM): time-based retention ≥365 days.

Verify: read back the policy and assert the 365-day rule is in effect.

6) Evidence & Outputs

Print PASS/FAIL for: table retention, export rule, blob presence/content, SA retention policy.

Artifacts: Terraform state, exported JSON of API reads, sample blob listing, and a short summary.

7) Success Criteria

All checks in §§3–5 PASS with evidence saved alongside Terraform config.

Background & Solution Notes (what this proves + cost comparison)
What this proves

Per-table retention is supported in LA: you can set 30 days Analytics and 365 days Total on a specific table; data older than Analytics but within Total is billed as long-term retention inside LA. 
Microsoft Learn

Data Export is table-based and writes JSONL per table to Storage as data arrives; you can include multiple tables in a single export rule. 
Microsoft Learn

Storage retention can be enforced by lifecycle (tier/delete) or immutability (WORM) with time-based retention. (Lifecycle delete doesn’t apply to immutable containers.) 
Microsoft Azure

Note (optional design, not in requirements): You can also dual-write upstream using Diagnostic settings from the source resource to LA and SA in parallel if you want an independent copy without relying on LA export. (Keep this out of the verification scope.)

Cost comparison (steady-state, simple model; USD list estimates)

Assumptions

Ingest 100 GB/day (≈3,000 GB/month).

Option A (LA-only): Keep 30d hot + 365d total (i.e., 335d LA long-term).

Option B (Export to SA): Keep 30d hot in LA (no LA long-term), export all data to SA, retain 365d in Cool tier.

Unit prices (USD, illustrative list):

LA ingestion (Pay-as-you-go): $2.30/GB. 
Microsoft Learn
+1

LA long-term retention: $0.10/GB-month (beyond included days). 
Thomas Stringer

LA Data Export: $0.10/GB exported. 
Microsoft Azure

Azure Blob (Cool) storage: ≈$0.01/GB-month (reference hot ≈$0.018/GB-month; Cool commonly ≈$0.01). Region pricing varies; validate for Australia East. 
Microsoft Azure
+1

Volumes at steady state

Daily ingest: 100 GB.

Option A LA long-term footprint: 335 days × 100 GB = 33,500 GB.

Option B SA footprint: 365 days × 100 GB = 36,500 GB.

Monthly cost (steady state)
Component	Option A: LA-only (30d hot + LA long-term to 365d)	Option B: LA 30d hot + Export→SA (365d in Cool)
LA ingestion (3,000 GB × $2.30)	$6,900	$6,900
LA long-term retention	33,500 GB × $0.10 = $3,350	$0
LA Data Export	$0	3,000 GB × $0.10 = $300
SA storage (Cool)	$0	36,500 GB × $0.01 = $365
Estimated monthly total	$10,250	$7,565
Delta vs A	—	Save ≈ $2,685 / month

Notes & caveats

Region & currency: Prices vary by region and currency; use the Azure Pricing Calculator to confirm Australia East specifics. 
Microsoft Azure

Query/restore/search costs (for LA long-term) and Storage operations/retrieval (for SA) are excluded here; include them for your workload pattern. LA Search Job/Query commonly bills per GB scanned (e.g., $0.005/GB). 
Microsoft Azure

Export cost is based on JSON bytes exported (1 GB = 10^9 bytes). 
Microsoft Azure

Rule of thumb

If you must keep 365d inside LA for analytics or compliance, expect to pay LA long-term rates.

If compliance allows object storage as the long-term system of record, 30d hot in LA + export to SA (Cool/WORM) is typically materially cheaper at steady state, while preserving a durable copy. 
Microsoft Learn

Deliverables you should end up with

Terraform for: RG, LA, SA, DCE/DCR (+ custom table), Data Export rule, SA lifecycle (or WORM).

One idempotent verification script (CLI/REST) that prints PASS/FAIL for: table retention, export rule, blob presence/content, SA retention policy.

The evidence bundle (API JSON outputs + blob listings).


# Document Generate

Generate a solution document in log_LA/documents/dcr_retention.md

* Illustrating the demo solution
* Generate diagram: illustrating log data lifecycle and compoenent it passing through, explain core compoenent like archive retention. different options. 
* Show the example code, and data got from Azure. like the JSON data, I want user actually see the option there.
* I want this document as solution doc, for team to understand the solution, with example code and data from this solution. as evidence. 
* Make it less verbose like AI generated. make it core, concise, avoid putting "fancy words" which have low info density. explain core idea, with example help reader to build mental model and understand. 
