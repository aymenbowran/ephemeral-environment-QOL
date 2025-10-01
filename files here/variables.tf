variable "environment_name" {
  description = "Name of the ephemeral environment (e.g., feature-123, demo-client-x)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment_name))
    error_message = "Environment name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

variable "ttl_hours" {
  description = "Time-to-live in hours before environment should be destroyed"
  type        = number
  default     = 4

  validation {
    condition     = var.ttl_hours > 0 && var.ttl_hours <= 168
    error_message = "TTL must be between 1 and 168 hours (7 days)."
  }
}

variable "owner" {
  description = "Owner of the environment (email or username)"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing purposes"
  type        = string
  default     = "ephemeral-environments"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "compute_subnet_prefix" {
  description = "Address prefix for compute subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "database_subnet_prefix" {
  description = "Address prefix for database subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "allowed_ssh_source" {
  description = "Source IP address or CIDR allowed for SSH access"
  type        = string
  default     = "*"
}

# Database Configuration
variable "enable_database" {
  description = "Whether to create a PostgreSQL database"
  type        = bool
  default     = true
}

variable "db_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "dbadmin"
}

variable "db_sku" {
  description = "SKU for PostgreSQL Flexible Server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "db_storage_mb" {
  description = "Storage size in MB for PostgreSQL"
  type        = number
  default     = 32768
}

# App Service Configuration
variable "enable_app_service" {
  description = "Whether to create an App Service"
  type        = bool
  default     = true
}

variable "app_service_sku" {
  description = "SKU for App Service Plan"
  type        = string
  default     = "B1"
}

variable "app_docker_image" {
  description = "Docker image for the web app"
  type        = string
  default     = "nginx"
}

variable "app_docker_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

variable "app_settings" {
  description = "Application settings for the web app"
  type        = map(string)
  default     = {}
}

# Container Registry Configuration
variable "enable_container_registry" {
  description = "Whether to create an Azure Container Registry"
  type        = bool
  default     = false
}

# Load Balancer Configuration
variable "enable_load_balancer" {
  description = "Whether to create a load balancer"
  type        = bool
  default     = false
}

# Cost Tracking
variable "enable_cost_tracking" {
  description = "Whether to enable cost management export"
  type        = bool
  default     = false
}

variable "cost_export_storage_container_id" {
  description = "Storage container ID for cost export (required if enable_cost_tracking is true)"
  type        = string
  default     = ""
}