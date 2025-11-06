terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "demo" {
  name     = "rg-la-dcr-demo"
  location = "australiaeast"
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "demo" {
  name                = "law-dcr-demo"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# User-Assigned Managed Identity
resource "azurerm_user_assigned_identity" "demo" {
  name                = "uami-dcr-demo"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
}

# Custom Table (DCR-based) - Created via Azure CLI
resource "null_resource" "create_custom_table" {
  provisioner "local-exec" {
    command = <<-EOT
      az monitor log-analytics workspace table create \
        --resource-group ${azurerm_resource_group.demo.name} \
        --workspace-name ${azurerm_log_analytics_workspace.demo.name} \
        --name corplog_CL \
        --columns TimeGenerated=datetime level=long message=string host=string environment=string attributes=dynamic \
        --plan Analytics || true
    EOT
  }

  depends_on = [azurerm_log_analytics_workspace.demo]
}

# Wait for table creation
resource "time_sleep" "wait_for_table" {
  depends_on = [null_resource.create_custom_table]
  create_duration = "30s"
}

# Data Collection Endpoint (required for ingestion)
resource "azurerm_monitor_data_collection_endpoint" "demo" {
  name                          = "dce-corplog-demo"
  resource_group_name           = azurerm_resource_group.demo.name
  location                      = azurerm_resource_group.demo.location
  public_network_access_enabled = true
  description                   = "Data Collection Endpoint for corplog DCR ingestion"
}

# Data Collection Rule
resource "azurerm_monitor_data_collection_rule" "demo" {
  name                        = "dcr-corplog-demo"
  location                    = azurerm_resource_group.demo.location
  resource_group_name         = azurerm_resource_group.demo.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.demo.id

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.demo.id
      name                  = "la-destination"
    }
  }

  data_flow {
    streams      = ["Custom-CorpLog"]
    destinations = ["la-destination"]
    transform_kql = "source | extend TimeGenerated = timestamp | project-away timestamp"
    output_stream = "Custom-corplog_CL"
  }

  stream_declaration {
    stream_name = "Custom-CorpLog"
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
      name = "host"
      type = "string"
    }
    column {
      name = "environment"
      type = "string"
    }
    column {
      name = "attributes"
      type = "dynamic"
    }
  }

  depends_on = [time_sleep.wait_for_table]
}

# Role Assignment: Monitoring Metrics Publisher on DCR
resource "azurerm_role_assignment" "dcr_publisher" {
  scope                = azurerm_monitor_data_collection_rule.demo.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.demo.principal_id
}

# Diagnostic Settings for DCR Metrics
resource "azurerm_monitor_diagnostic_setting" "dcr_metrics" {
  name                       = "dcr-diagnostics"
  target_resource_id         = azurerm_monitor_data_collection_rule.demo.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.demo.id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
