terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateephem"
    container_name      = "tfstate"
    key                 = "ephemeral-envs.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

locals {
  common_tags = merge(
    var.tags,
    {
      Environment   = var.environment_name
      ManagedBy     = "Terraform"
      Project       = "EphemeralEnvironments"
      CreatedAt     = timestamp()
      TTL           = var.ttl_hours
      Owner         = var.owner
      CostCenter    = var.cost_center
      AutoDestroy   = "true"
      DestroyAfter  = timeadd(timestamp(), "${var.ttl_hours}h")
    }
  )

  # Generate unique identifier for this environment
  env_id = lower("${var.environment_name}-${random_string.env_suffix.result}")
}

# Random suffix to ensure uniqueness
resource "random_string" "env_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "ephemeral" {
  name     = "rg-${local.env_id}"
  location = var.location
  tags     = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedAt"]]
  }
}

# Virtual Network
resource "azurerm_virtual_network" "ephemeral" {
  name                = "vnet-${local.env_id}"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.ephemeral.location
  resource_group_name = azurerm_resource_group.ephemeral.name
  tags                = local.common_tags
}

# Subnet for compute resources
resource "azurerm_subnet" "compute" {
  name                 = "snet-compute-${local.env_id}"
  resource_group_name  = azurerm_resource_group.ephemeral.name
  virtual_network_name = azurerm_virtual_network.ephemeral.name
  address_prefixes     = [var.compute_subnet_prefix]
}

# Subnet for database
resource "azurerm_subnet" "database" {
  name                 = "snet-database-${local.env_id}"
  resource_group_name  = azurerm_resource_group.ephemeral.name
  virtual_network_name = azurerm_virtual_network.ephemeral.name
  address_prefixes     = [var.database_subnet_prefix]

  delegation {
    name = "postgresql-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Network Security Group
resource "azurerm_network_security_group" "ephemeral" {
  name                = "nsg-${local.env_id}"
  location            = azurerm_resource_group.ephemeral.location
  resource_group_name = azurerm_resource_group.ephemeral.name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_source
    destination_address_prefix = "*"
  }
}

# Associate NSG with compute subnet
resource "azurerm_subnet_network_security_group_association" "compute" {
  subnet_id                 = azurerm_subnet.compute.id
  network_security_group_id = azurerm_network_security_group.ephemeral.id
}

# Public IP for Load Balancer
resource "azurerm_public_ip" "lb" {
  count               = var.enable_load_balancer ? 1 : 0
  name                = "pip-lb-${local.env_id}"
  location            = azurerm_resource_group.ephemeral.location
  resource_group_name = azurerm_resource_group.ephemeral.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "ephemeral" {
  count               = var.enable_database ? 1 : 0
  name                = "psql-${local.env_id}"
  resource_group_name = azurerm_resource_group.ephemeral.name
  location            = azurerm_resource_group.ephemeral.location

  administrator_login    = var.db_admin_username
  administrator_password = random_password.db_password[0].result

  sku_name   = var.db_sku
  version    = "14"
  storage_mb = var.db_storage_mb

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  delegated_subnet_id = azurerm_subnet.database.id
  private_dns_zone_id = azurerm_private_dns_zone.postgresql[0].id

  tags = local.common_tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}

# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgresql" {
  count               = var.enable_database ? 1 : 0
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.ephemeral.name
  tags                = local.common_tags
}

# Link Private DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  count                 = var.enable_database ? 1 : 0
  name                  = "pdns-link-${local.env_id}"
  private_dns_zone_name = azurerm_private_dns_zone.postgresql[0].name
  virtual_network_id    = azurerm_virtual_network.ephemeral.id
  resource_group_name   = azurerm_resource_group.ephemeral.name
  tags                  = local.common_tags
}

# Random password for database
resource "random_password" "db_password" {
  count   = var.enable_database ? 1 : 0
  length  = 32
  special = true
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "app" {
  count     = var.enable_database ? 1 : 0
  name      = "appdb"
  server_id = azurerm_postgresql_flexible_server.ephemeral[0].id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Container Registry (optional)
resource "azurerm_container_registry" "ephemeral" {
  count               = var.enable_container_registry ? 1 : 0
  name                = "acr${replace(local.env_id, "-", "")}"
  resource_group_name = azurerm_resource_group.ephemeral.name
  location            = azurerm_resource_group.ephemeral.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = local.common_tags
}

# App Service Plan
resource "azurerm_service_plan" "ephemeral" {
  count               = var.enable_app_service ? 1 : 0
  name                = "asp-${local.env_id}"
  resource_group_name = azurerm_resource_group.ephemeral.name
  location            = azurerm_resource_group.ephemeral.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = local.common_tags
}

# Web App
resource "azurerm_linux_web_app" "ephemeral" {
  count               = var.enable_app_service ? 1 : 0
  name                = "app-${local.env_id}"
  resource_group_name = azurerm_resource_group.ephemeral.name
  location            = azurerm_service_plan.ephemeral[0].location
  service_plan_id     = azurerm_service_plan.ephemeral[0].id
  tags                = local.common_tags

  site_config {
    always_on = false

    application_stack {
      docker_image     = var.app_docker_image
      docker_image_tag = var.app_docker_tag
    }
  }

  app_settings = merge(
    var.app_settings,
    var.enable_database ? {
      DATABASE_URL = "postgresql://${var.db_admin_username}:${random_password.db_password[0].result}@${azurerm_postgresql_flexible_server.ephemeral[0].fqdn}:5432/appdb"
    } : {}
  )
}

# Time offset for auto-deletion
resource "time_offset" "deletion_time" {
  offset_hours = var.ttl_hours
}

# Cost tracking - Azure Cost Management Export (requires setup)
resource "azurerm_resource_group_cost_management_export" "ephemeral" {
  count              = var.enable_cost_tracking ? 1 : 0
  name               = "cost-export-${local.env_id}"
  resource_group_id  = azurerm_resource_group.ephemeral.id
  recurrence_type    = "Daily"
  recurrence_period_start_date = formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timestamp())
  recurrence_period_end_date   = formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timeadd(timestamp(), "${var.ttl_hours}h"))

  export_data_storage_location {
    container_id     = var.cost_export_storage_container_id
    root_folder_path = "/ephemeral-costs/${local.env_id}"
  }

  export_data_options {
    type       = "ActualCost"
    time_frame = "Custom"
  }
}