#!/usr/bin/env python3
"""
Azure Log Analytics DCR Ingestion Verification Script

This script sends three test cases to validate DCR ingestion:
1. Valid minimal (flat) log - required fields only
2. Valid nested log - includes nested attributes
3. Invalid log - contains unexpected root field (should be dropped)

IMPORTANT: This script uses User-Assigned Managed Identity (UAMI) for authentication,
NOT admin/user credentials. The UAMI must have "Monitoring Metrics Publisher" role on the DCR.
"""

import sys
import os
import time
from datetime import datetime, timezone
from azure.identity import ManagedIdentityCredential
from azure.monitor.ingestion import LogsIngestionClient
from azure.core.exceptions import HttpResponseError


def get_terraform_output(key: str) -> str:
    """
    Helper to retrieve Terraform outputs.
    Run this from terraform directory or provide values manually.
    """
    import subprocess
    import json

    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd="terraform",
            capture_output=True,
            text=True,
            check=True
        )
        outputs = json.loads(result.stdout)
        return outputs[key]["value"]
    except Exception as e:
        print(f"Error retrieving Terraform output '{key}': {e}")
        print("Run 'terraform output' in the terraform directory to get required values")
        sys.exit(1)


def main():
    print("=== Azure DCR Log Ingestion Verification ===\n")

    # Retrieve configuration from Terraform outputs
    print("Retrieving configuration from Terraform outputs...")
    dcr_immutable_id = get_terraform_output("dcr_immutable_id")
    dcr_endpoint = get_terraform_output("dcr_ingestion_endpoint")
    stream_name = get_terraform_output("stream_name")
    uami_client_id = get_terraform_output("managed_identity_client_id")

    print(f"DCR Immutable ID: {dcr_immutable_id}")
    print(f"DCR Endpoint: {dcr_endpoint}")
    print(f"Stream Name: {stream_name}")
    print(f"UAMI Client ID: {uami_client_id}\n")

    # Initialize Azure credentials
    # Priority: Try UAMI first (for Azure VM/resources), fallback to AzureCliCredential (for local dev)
    print("Initializing Azure credentials...")

    credential = None
    auth_method = None

    # Try UAMI first (for production use on Azure resources)
    try:
        print(f"  → Attempting UAMI authentication (client_id: {uami_client_id})...")
        uami_credential = ManagedIdentityCredential(client_id=uami_client_id)
        token = uami_credential.get_token("https://monitor.azure.com/.default")
        credential = uami_credential
        auth_method = "UAMI (User-Assigned Managed Identity)"
        print(f"  ✓ Successfully authenticated with UAMI")
        print(f"  ✓ Token acquired (expires in ~{(token.expires_on - time.time())//60:.0f} minutes)")
    except Exception as uami_error:
        print(f"  ℹ UAMI not available (expected on local dev machine): {str(uami_error)[:100]}")

        # Fallback to Azure CLI credentials for local development
        try:
            from azure.identity import AzureCliCredential
            print(f"  → Attempting Azure CLI credential (fallback for local dev)...")
            cli_credential = AzureCliCredential()
            token = cli_credential.get_token("https://monitor.azure.com/.default")
            credential = cli_credential
            auth_method = "Azure CLI (az login)"
            print(f"  ✓ Successfully authenticated with Azure CLI")
            print(f"  ✓ Token acquired (expires in ~{(token.expires_on - time.time())//60:.0f} minutes)")
            print(f"  ⚠ NOTE: Using admin credentials for local testing")
            print(f"  ⚠ In production, UAMI with client_id {uami_client_id} should be used")
        except Exception as cli_error:
            print(f"  ✗ Failed to authenticate with Azure CLI: {cli_error}")
            print("\nNo valid credentials available. Please:")
            print("1. Run 'az login' for local development, OR")
            print("2. Run this script on an Azure resource with UAMI attached")
            sys.exit(1)

    print(f"\n  📋 Authentication Method: {auth_method}\n")

    print("Creating Logs Ingestion client...")
    client = LogsIngestionClient(endpoint=dcr_endpoint, credential=credential)

    # Test Case 1: Valid minimal (flat) log
    print("\n--- Test Case 1: Valid Minimal (Flat) Log ---")
    log_entry_1 = [{
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": 6,  # syslog INFO
        "message": "Test log entry - minimal flat structure",
        "host": "test-host-01",
        "environment": "dev"
    }]

    try:
        print(f"Sending: {log_entry_1[0]}")
        client.upload(
            rule_id=dcr_immutable_id,
            stream_name=stream_name,
            logs=log_entry_1
        )
        print("✓ Successfully sent Test Case 1 (flat log)")
    except HttpResponseError as e:
        print(f"✗ Failed to send Test Case 1: {e}")
        print(f"  Error details: {e.error}")

    time.sleep(1)

    # Test Case 2: Valid log with nested attributes
    print("\n--- Test Case 2: Valid Nested Log (with attributes) ---")
    log_entry_2 = [{
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": 4,  # syslog WARNING
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

    try:
        print(f"Sending: {log_entry_2[0]}")
        client.upload(
            rule_id=dcr_immutable_id,
            stream_name=stream_name,
            logs=log_entry_2
        )
        print("✓ Successfully sent Test Case 2 (nested log)")
    except HttpResponseError as e:
        print(f"✗ Failed to send Test Case 2: {e}")
        print(f"  Error details: {e.error}")

    time.sleep(1)

    # Test Case 3: Invalid log with unexpected root field
    print("\n--- Test Case 3: Invalid Log (unexpected root field) ---")
    log_entry_3 = [{
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": 3,  # syslog ERROR
        "message": "Test log entry - invalid with unexpected field",
        "host": "test-host-03",
        "environment": "prod",
        "unexpected_field": "This should cause the log to be dropped",  # NOT allowed at root
        "another_bad_field": 999
    }]

    try:
        print(f"Sending: {log_entry_3[0]}")
        client.upload(
            rule_id=dcr_immutable_id,
            stream_name=stream_name,
            logs=log_entry_3
        )
        print("✓ Request accepted by API (but should be dropped by DCR transform)")
        print("  Check DCR metrics for RowsDropped/TransformationErrors")
    except HttpResponseError as e:
        print(f"✗ Failed to send Test Case 3: {e}")
        print(f"  Error details: {e.error}")

    # Summary
    print("\n=== Verification Summary ===")
    print("Three test logs have been sent to the DCR:")
    print("1. ✓ Valid flat log (should appear in corplog_cl)")
    print("2. ✓ Valid nested log with attributes (should appear in corplog_cl)")
    print("3. ⚠ Invalid log with unexpected root fields (should be DROPPED)")
    print("\nNext steps:")
    print("1. Wait 2-5 minutes for ingestion to complete")
    print("2. Query Log Analytics:")
    print("   corplog_cl | where TimeGenerated > ago(10m)")
    print("3. Check DCR metrics in Azure Portal:")
    print("   - RowsReceived (should show 3)")
    print("   - RowsDropped (should show 1 for invalid log)")
    print("   - TransformationErrors (may show 1)")
    print("4. Verify attributes column contains nested JSON for Test Case 2:")
    print("   corplog_cl | where message contains 'nested' | project attributes")


if __name__ == "__main__":
    main()
