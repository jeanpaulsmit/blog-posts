# Configure the provider
provider "azurerm" {
  version = "=2.1.0"
  features {}
}

# Specify location to store tfstate files
# To use 'local' (which is local folder) just disable this section
# terraform {
#   backend "azurerm" {
#   }
# }

# Constructed names of resources
locals {
    resourceGroupName  = "${var.prefix}-${var.resourceFunction}-${var.environment}-${var.region}"
    storageAccountName = "${var.prefix}${var.resourceFunction}sa${var.environment}${var.region}"
}

# Create a new resource group
resource "azurerm_resource_group" "rg" {
  name     = local.resourceGroupName
  location = var.location
  tags     = var.tags
}

# --- Storage Account section --
# Create storage account to store policy files and other deployment related files
resource "azurerm_storage_account" "sa" {
  name                     = local.storageAccountName
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = var.storageAccountSku.tier
  account_replication_type = var.storageAccountSku.type
  account_kind             = "StorageV2"
  enable_https_traffic_only= true
  tags                     = var.tags
}
resource "azurerm_storage_container" "saContainerApim" {
  name                  = "apim-files"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}
resource "azurerm_storage_container" "saContainerApi" {
  name                  = "api-files"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

# --- Output section --
output "storageAccountName" {
  value = azurerm_storage_account.sa.name
}
