output "resource_group_name" {
  value       = azurerm_resource_group.retention_demo.name
  description = "Resource group name"
}

output "workspace_name" {
  value       = azurerm_log_analytics_workspace.retention_demo.name
  description = "Log Analytics workspace name"
}

output "workspace_id" {
  value       = azurerm_log_analytics_workspace.retention_demo.workspace_id
  description = "Log Analytics workspace ID (GUID)"
}

output "storage_account_name" {
  value       = azurerm_storage_account.logs.name
  description = "Storage account name for exported logs"
}

output "dcr_immutable_id" {
  value       = azurerm_monitor_data_collection_rule.retention_demo.immutable_id
  description = "DCR immutable ID for ingestion"
}

output "dcr_ingestion_endpoint" {
  value       = azurerm_monitor_data_collection_endpoint.retention_demo.logs_ingestion_endpoint
  description = "DCR ingestion endpoint URL"
}

output "stream_name" {
  value       = "Custom-TestExport"
  description = "DCR stream name for log ingestion"
}

output "table_name" {
  value       = "testexport_CL"
  description = "Custom table name in Log Analytics"
}

output "export_rule_name" {
  value       = azurerm_log_analytics_data_export_rule.test_export.name
  description = "Data export rule name"
}

output "uami_client_id" {
  value       = azurerm_user_assigned_identity.retention_demo.client_id
  description = "User-assigned managed identity client ID"
}
