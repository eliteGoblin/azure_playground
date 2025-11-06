#!/usr/bin/env python3
"""
Ship test logs to TestExport_CL table for retention/export verification.
"""

import os
import sys
import subprocess
import time
from datetime import datetime, timezone
from azure.monitor.ingestion import LogsIngestionClient
from azure.identity import DefaultAzureCredential
from azure.core.exceptions import HttpResponseError

def get_terraform_output(output_name):
    """Get Terraform output value."""
    try:
        result = subprocess.check_output(
            ["terraform", "output", "-raw", output_name],
            cwd="terraform",
            stderr=subprocess.DEVNULL
        )
        return result.decode().strip()
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to get Terraform output '{output_name}': {e}")
        sys.exit(1)

def ship_logs(client, dcr_id, stream_name, logs, batch_name):
    """Ship logs to DCR and handle errors."""
    print(f"\n📤 Shipping {len(logs)} logs ({batch_name})...")

    try:
        client.upload(
            rule_id=dcr_id,
            stream_name=stream_name,
            logs=logs
        )
        print(f"✅ Successfully shipped {len(logs)} logs - HTTP 204")
        return True
    except HttpResponseError as e:
        print(f"❌ Failed to ship logs: HTTP {e.status_code}")
        print(f"   Error: {e.message}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def main():
    print("=== LA Retention Demo - Test Log Ingestion ===\n")

    # Get Terraform outputs
    print("📋 Reading Terraform outputs...")
    dcr_endpoint = get_terraform_output("dcr_ingestion_endpoint")
    dcr_id = get_terraform_output("dcr_immutable_id")
    stream_name = get_terraform_output("stream_name")
    table_name = get_terraform_output("table_name")

    print(f"   DCR Endpoint: {dcr_endpoint}")
    print(f"   DCR ID: {dcr_id}")
    print(f"   Stream: {stream_name}")
    print(f"   Table: {table_name}")

    # Authenticate
    print("\n🔐 Authenticating...")
    credential = DefaultAzureCredential()
    client = LogsIngestionClient(endpoint=dcr_endpoint, credential=credential)
    print("✅ Authenticated using DefaultAzureCredential (az login session)")

    # Create initial batch of 10 test logs
    print("\n=== Phase 1: Initial Batch (10 logs) ===")
    initial_logs = []
    test_id_1 = f"test-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}"

    for i in range(10):
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": 6,  # INFO
            "message": f"Initial test log entry {i+1}/10",
            "test_id": test_id_1,
            "sequence": i + 1
        }
        initial_logs.append(log_entry)
        time.sleep(0.1)  # Small delay for timestamp variation

    if not ship_logs(client, dcr_id, stream_name, initial_logs, "Initial Batch"):
        sys.exit(1)

    # Wait before second batch
    print("\n⏱️  Waiting 5 seconds before second batch...")
    time.sleep(5)

    # Create delta batch of 5 additional logs (for export verification)
    print("\n=== Phase 2: Delta Batch (5 logs) ===")
    print("(Enable export rule, then run this batch to verify export works)")

    delta_logs = []
    test_id_2 = f"delta-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}"

    for i in range(5):
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": 4,  # WARNING
            "message": f"Delta test log entry {i+1}/5 - for export verification",
            "test_id": test_id_2,
            "sequence": 100 + i + 1
        }
        delta_logs.append(log_entry)
        time.sleep(0.1)

    if not ship_logs(client, dcr_id, stream_name, delta_logs, "Delta Batch"):
        sys.exit(1)

    # Summary
    print("\n=== Summary ===")
    print(f"✅ Total logs sent: 15")
    print(f"   Initial batch: 10 logs (test_id: {test_id_1})")
    print(f"   Delta batch: 5 logs (test_id: {test_id_2})")
    print("\n📊 Verification:")
    print(f"   Wait 2-5 minutes for ingestion")
    print(f"   Run: ./verify_retention.sh")
    print(f"\n   Or query manually:")
    print(f"   {table_name} | where test_id in ('{test_id_1}', '{test_id_2}') | order by TimeGenerated asc")

if __name__ == "__main__":
    main()
