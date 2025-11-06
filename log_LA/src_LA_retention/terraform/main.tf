terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Random suffix for unique names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "retention_demo" {
  name     = "rg-la-retention-${random_string.suffix.result}"
  location = "australiaeast"
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "retention_demo" {
  name                = "law-retention-${random_string.suffix.result}"
  location            = azurerm_resource_group.retention_demo.location
  resource_group_name = azurerm_resource_group.retention_demo.name
  sku                 = "PerGB2018"
  retention_in_days   = 30  # Workspace default
}

# Storage Account for Data Export
resource "azurerm_storage_account" "logs" {
  name                     = "salogret${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.retention_demo.name
  location                 = azurerm_resource_group.retention_demo.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Cool"  # Cool tier for cheaper long-term storage

  # Enable blob versioning for immutability support
  blob_properties {
    versioning_enabled = true
  }
}

# Storage Lifecycle Management Policy (365 days retention)
resource "azurerm_storage_management_policy" "retention_policy" {
  storage_account_id = azurerm_storage_account.logs.id

  rule {
    name    = "delete-after-365-days"
    enabled = true

    filters {
      prefix_match = ["am-"]  # Exported LA data has "am-" prefix
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = 365
      }
    }
  }
}

# Data Collection Endpoint (required for ingestion)
resource "azurerm_monitor_data_collection_endpoint" "retention_demo" {
  name                          = "dce-retention-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.retention_demo.name
  location                      = azurerm_resource_group.retention_demo.location
  public_network_access_enabled = true
}

# Create custom table first (before DCR)
resource "null_resource" "create_test_table_first" {
  provisioner "local-exec" {
    command = <<-EOT
      az monitor log-analytics workspace table create \
        --resource-group ${azurerm_resource_group.retention_demo.name} \
        --workspace-name ${azurerm_log_analytics_workspace.retention_demo.name} \
        --name testexport_CL \
        --retention-time 30 \
        --total-retention-time 365 \
        --columns TimeGenerated=datetime level=long message=string test_id=string sequence=long \
        --plan Analytics || true
    EOT
  }

  depends_on = [azurerm_log_analytics_workspace.retention_demo]
}

# Wait for table to be fully provisioned
resource "time_sleep" "wait_for_table" {
  create_duration = "30s"
  depends_on      = [null_resource.create_test_table_first]
}

# Data Collection Rule with custom table
resource "azurerm_monitor_data_collection_rule" "retention_demo" {
  name                        = "dcr-retention-${random_string.suffix.result}"
  resource_group_name         = azurerm_resource_group.retention_demo.name
  location                    = azurerm_resource_group.retention_demo.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.retention_demo.id

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.retention_demo.id
      name                  = "la-destination"
    }
  }

  data_flow {
    streams       = ["Custom-TestExport"]
    destinations  = ["la-destination"]
    transform_kql = "source | extend TimeGenerated = timestamp | project-away timestamp"
    output_stream = "Custom-testexport_CL"
  }

  stream_declaration {
    stream_name = "Custom-TestExport"
    column {
      name = "timestamp"
      type = "datetime"
    }
    column {
      name = "level"
      type = "long"
    }
    column {
      name = "message"
      type = "string"
    }
    column {
      name = "test_id"
      type = "string"
    }
    column {
      name = "sequence"
      type = "long"
    }
  }

  depends_on = [time_sleep.wait_for_table]
}


# User-Assigned Managed Identity for DCR
resource "azurerm_user_assigned_identity" "retention_demo" {
  name                = "uami-retention-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.retention_demo.name
  location            = azurerm_resource_group.retention_demo.location
}

# Role assignment: Monitoring Metrics Publisher on DCR
resource "azurerm_role_assignment" "dcr_publisher" {
  scope                = azurerm_monitor_data_collection_rule.retention_demo.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.retention_demo.principal_id
}

# Data Export Rule: LA → Storage Account
resource "azurerm_log_analytics_data_export_rule" "test_export" {
  name                    = "export-testexport-${random_string.suffix.result}"
  resource_group_name     = azurerm_resource_group.retention_demo.name
  workspace_resource_id   = azurerm_log_analytics_workspace.retention_demo.id
  destination_resource_id = azurerm_storage_account.logs.id
  table_names             = ["testexport_CL"]
  enabled                 = true

  depends_on = [null_resource.create_test_table_first]
}
