#!/usr/bin/env python3
"""
Ship logs to Azure Log Analytics DCR using admin credentials (az login session)
"""

import sys
import time
from datetime import datetime, timezone
from azure.identity import DefaultAzureCredential
from azure.monitor.ingestion import LogsIngestionClient
from azure.core.exceptions import HttpResponseError
import subprocess
import json


def get_terraform_output(key: str) -> str:
    """Retrieve Terraform outputs."""
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
        sys.exit(1)


def main():
    print("=== Azure DCR Log Ingestion (Admin Credentials) ===\n")

    # Get configuration from Terraform
    print("Retrieving configuration from Terraform outputs...")
    dcr_immutable_id = get_terraform_output("dcr_immutable_id")
    dcr_endpoint = get_terraform_output("dcr_ingestion_endpoint")
    stream_name = get_terraform_output("stream_name")

    print(f"DCR Immutable ID: {dcr_immutable_id}")
    print(f"DCR Endpoint: {dcr_endpoint}")
    print(f"Stream Name: {stream_name}\n")

    # Use DefaultAzureCredential (picks up az login session)
    print("Authenticating with Azure (using az login session)...")
    credential = DefaultAzureCredential()

    # Test authentication
    try:
        token = credential.get_token("https://monitor.azure.com/.default")
        print(f"✓ Authenticated successfully with admin credentials")
        print(f"✓ Token acquired (expires in ~{(token.expires_on - time.time())//60:.0f} minutes)\n")
    except Exception as e:
        print(f"✗ Authentication failed: {e}")
        print("Make sure you've run 'az login'")
        sys.exit(1)

    # Create ingestion client
    print("Creating Logs Ingestion client...\n")
    client = LogsIngestionClient(endpoint=dcr_endpoint, credential=credential)

    # Test Case 1: Valid minimal (flat) log
    print("--- Test Case 1: Valid Minimal (Flat) Log ---")
    log_entry_1 = [{
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": 6,
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
        print("✓ Successfully sent Test Case 1 (flat log)\n")
    except HttpResponseError as e:
        print(f"✗ Failed to send Test Case 1: {e}\n")

    time.sleep(1)

    # Test Case 2: Valid log with nested attributes
    print("--- Test Case 2: Valid Nested Log (with attributes) ---")
    log_entry_2 = [{
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": 4,
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
        print(f"Sending nested log with attributes...")
        client.upload(
            rule_id=dcr_immutable_id,
            stream_name=stream_name,
            logs=log_entry_2
        )
        print("✓ Successfully sent Test Case 2 (nested log)\n")
    except HttpResponseError as e:
        print(f"✗ Failed to send Test Case 2: {e}\n")

    time.sleep(1)

    # Test Case 3: Invalid log with unexpected root field (should be dropped by DCR transform)
    print("--- Test Case 3: Invalid Log (unexpected root field) ---")
    log_entry_3 = [{
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": 3,
        "message": "Test log entry - invalid with unexpected field",
        "host": "test-host-03",
        "environment": "prod",
        "unexpected_field": "This should cause the log to be dropped",
        "another_bad_field": 999
    }]

    try:
        print(f"Sending invalid log (has unexpected root fields)...")
        client.upload(
            rule_id=dcr_immutable_id,
            stream_name=stream_name,
            logs=log_entry_3
        )
        print("✓ Request accepted by API (but MAY be dropped by DCR transform)")
        print("  Check DCR metrics for RowsDropped/TransformationErrors\n")
    except HttpResponseError as e:
        print(f"✗ Failed to send Test Case 3: {e}\n")

    # Summary
    print("=== Log Shipping Complete ===")
    print("\nNext steps:")
    print("1. Wait 2-5 minutes for ingestion to complete")
    print("2. Run verification script to query logs")
    print("3. Check DCR metrics for rows received/dropped")


if __name__ == "__main__":
    main()
