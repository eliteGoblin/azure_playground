#!/usr/bin/env python3
"""
Ship logs using UAMI - designed to run on Azure Container Instance
This script explicitly uses the UAMI (not admin credentials)
"""

import os
import sys
import time
from datetime import datetime, timezone
from azure.identity import ManagedIdentityCredential
from azure.monitor.ingestion import LogsIngestionClient
from azure.core.exceptions import HttpResponseError

# Get config from environment variables (set by container)
DCR_ID = os.environ['DCR_IMMUTABLE_ID']
DCR_ENDPOINT = os.environ['DCR_ENDPOINT']
STREAM_NAME = os.environ['STREAM_NAME']
UAMI_CLIENT_ID = os.environ['UAMI_CLIENT_ID']

print(f"=== Shipping Logs via UAMI ===")
print(f"DCR ID: {DCR_ID}")
print(f"DCR Endpoint: {DCR_ENDPOINT}")
print(f"Stream: {STREAM_NAME}")
print(f"UAMI Client ID: {UAMI_CLIENT_ID}\n")

# Use UAMI (will only work on Azure resources with UAMI attached)
print("Authenticating with UAMI...")
credential = ManagedIdentityCredential(client_id=UAMI_CLIENT_ID)

# Test authentication
try:
    token = credential.get_token("https://monitor.azure.com/.default")
    print(f"✓ UAMI authenticated successfully")
    print(f"✓ Token expires in ~{(token.expires_on - time.time())//60:.0f} minutes\n")
except Exception as e:
    print(f"✗ UAMI authentication failed: {e}")
    sys.exit(1)

# Create client
client = LogsIngestionClient(endpoint=DCR_ENDPOINT, credential=credential)

# Ship test logs
logs = [
    {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": 6,
        "message": "UAMI test log - minimal flat",
        "host": "container-instance",
        "environment": "prod"
    },
    {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": 4,
        "message": "UAMI test log - with nested attributes",
        "host": "container-instance",
        "environment": "prod",
        "attributes": {
            "shipped_by": "uami",
            "client_id": UAMI_CLIENT_ID,
            "nested": {"level2": {"level3": "deep_value"}}
        }
    }
]

for i, log in enumerate(logs, 1):
    print(f"Shipping log {i}...")
    try:
        client.upload(rule_id=DCR_ID, stream_name=STREAM_NAME, logs=[log])
        print(f"✓ Log {i} shipped successfully via UAMI\n")
    except Exception as e:
        print(f"✗ Failed to ship log {i}: {e}\n")

print("=== UAMI Log Shipping Complete ===")
