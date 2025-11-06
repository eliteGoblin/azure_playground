output "dcr_immutable_id" {
  description = "Data Collection Rule immutable ID"
  value       = azurerm_monitor_data_collection_rule.demo.immutable_id
}

output "dcr_ingestion_endpoint" {
  description = "DCR ingestion endpoint URL (via DCE)"
  value       = azurerm_monitor_data_collection_endpoint.demo.logs_ingestion_endpoint
}

output "stream_name" {
  description = "Custom stream name for log ingestion"
  value       = "Custom-CorpLog"
}

output "workspace_id" {
  description = "Log Analytics Workspace ID"
  value       = azurerm_log_analytics_workspace.demo.workspace_id
}

output "workspace_resource_id" {
  description = "Log Analytics Workspace resource ID"
  value       = azurerm_log_analytics_workspace.demo.id
}

output "managed_identity_client_id" {
  description = "User-Assigned Managed Identity client ID"
  value       = azurerm_user_assigned_identity.demo.client_id
}

output "managed_identity_principal_id" {
  description = "User-Assigned Managed Identity principal ID"
  value       = azurerm_user_assigned_identity.demo.principal_id
}

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.demo.name
}

output "table_name" {
  description = "Custom table name"
  value       = "corplog_CL"
}
