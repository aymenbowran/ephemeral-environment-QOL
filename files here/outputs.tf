output "environment_id" {
  description = "Unique identifier for this environment"
  value       = local.env_id
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.ephemeral.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.ephemeral.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.ephemeral.location
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.ephemeral.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.ephemeral.name
}

output "app_service_url" {
  description = "URL of the App Service"
  value       = var.enable_app_service ? "https://${azurerm_linux_web_app.ephemeral[0].default_hostname}" : null
}

output "app_service_name" {
  description = "Name of the App Service"
  value       = var.enable_app_service ? azurerm_linux_web_app.ephemeral[0].name : null
}

output "database_fqdn" {
  description = "Fully qualified domain name of the PostgreSQL server"
  value       = var.enable_database ? azurerm_postgresql_flexible_server.ephemeral[0].fqdn : null
  sensitive   = true
}

output "database_name" {
  description = "Name of the PostgreSQL database"
  value       = var.enable_database ? azurerm_postgresql_flexible_server_database.app[0].name : null
}

output "database_username" {
  description = "Database administrator username"
  value       = var.enable_database ? var.db_admin_username : null
  sensitive   = true
}

output "database_password" {
  description = "Database administrator password"
  value       = var.enable_database ? random_password.db_password[0].result : null
  sensitive   = true
}

output "database_connection_string" {
  description = "Full database connection string"
  value       = var.enable_database ? "postgresql://${var.db_admin_username}:${random_password.db_password[0].result}@${azurerm_postgresql_flexible_server.ephemeral[0].fqdn}:5432/appdb" : null
  sensitive   = true
}

output "container_registry_login_server" {
  description = "Login server for the container registry"
  value       = var.enable_container_registry ? azurerm_container_registry.ephemeral[0].login_server : null
}

output "container_registry_admin_username" {
  description = "Admin username for the container registry"
  value       = var.enable_container_registry ? azurerm_container_registry.ephemeral[0].admin_username : null
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "Admin password for the container registry"
  value       = var.enable_container_registry ? azurerm_container_registry.ephemeral[0].admin_password : null
  sensitive   = true
}

output "load_balancer_ip" {
  description = "Public IP address of the load balancer"
  value       = var.enable_load_balancer ? azurerm_public_ip.lb[0].ip_address : null
}

output "created_at" {
  description = "Timestamp when the environment was created"
  value       = timestamp()
}

output "destroy_after" {
  description = "Timestamp when the environment should be destroyed"
  value       = timeadd(timestamp(), "${var.ttl_hours}h")
}

output "ttl_hours" {
  description = "Time-to-live in hours"
  value       = var.ttl_hours
}

output "owner" {
  description = "Owner of the environment"
  value       = var.owner
}

output "cost_center" {
  description = "Cost center for billing"
  value       = var.cost_center
}

output "tags" {
  description = "All tags applied to resources"
  value       = local.common_tags
}

output "quick_start_guide" {
  description = "Quick start information"
  value = <<-EOT
    Environment Created Successfully!
    =================================
    
    Environment ID: ${local.env_id}
    Owner: ${var.owner}
    TTL: ${var.ttl_hours} hours
    Destroy After: ${timeadd(timestamp(), "${var.ttl_hours}h")}
    
    ${var.enable_app_service ? "Web App URL: https://${azurerm_linux_web_app.ephemeral[0].default_hostname}" : ""}
    ${var.enable_database ? "Database: ${azurerm_postgresql_flexible_server.ephemeral[0].fqdn}" : ""}
    
    To destroy this environment:
    terraform destroy -auto-approve
    
    To extend TTL, update ttl_hours variable and run:
    terraform apply -auto-approve
  EOT
}