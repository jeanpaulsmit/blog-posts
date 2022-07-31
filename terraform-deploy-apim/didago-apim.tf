
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
  apimName          = "${var.prefix}-${var.resourceFunction}-${var.environment}-${var.region}"
  kvName             = "${var.prefix}-${var.resourceFunction}-kv-${var.environment}-${var.region}"
  appInsightsName    = "${var.prefix}-${var.resourceFunction}-appinsights-${var.environment}-${var.region}"
}

# --- Get reference to logged on Azure subscription ---
data "azurerm_client_config" "current" {}

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

# --- Key Vault section
# Create Key Vault
resource "azurerm_key_vault" "kv" {
  name                        = local.kvName
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = false
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  tags                        = var.tags
  sku_name                    = "standard"
}
# Assign get certificate permissions to the executing account so it can access it
resource "azurerm_key_vault_access_policy" "kvPermissions" {
  key_vault_id = azurerm_key_vault.kv.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "get"
  ]

  # Give full control to the sevice principal as it might need to delete a certificate on the next update run
  certificate_permissions = [
    "create",
    "delete",
    "get",
    "import",
    "list",
    "update"
  ]
}

# Upload certificate to Key vault
resource "azurerm_key_vault_certificate" "kvCertificate" {
  name         = "apim-tls-certificate"
  key_vault_id = azurerm_key_vault.kv.id

  certificate {
    contents = filebase64("certificates/${var.apimProxyHostConfig.certificateName}")
    password = var.apimProxyHostConfig.certificatePasword
  }

  certificate_policy {
    issuer_parameters {
      name = var.apimProxyHostConfig.certificateIssuer
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }
  }
}

# --- API Management section --
# Create a new APIM instance
resource "azurerm_api_management" "apim" {
  name                = local.apimName
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_name      = var.apimPublisherName
  publisher_email     = var.apimPublisherEmail
  tags                = var.tags

  sku_name            = "${var.apimSku}_${var.apimSkuCapacity}"

  identity {
    type = "SystemAssigned"
  }

  # policy {
  #   xml_link = var.tenantPolicyUrl
  # }
}

# Assign get certificate permissions to APIM managed identity so it can access the certificate in key vault
resource "azurerm_key_vault_access_policy" "kvApimPolicy" {
  key_vault_id = azurerm_key_vault.kv.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azurerm_api_management.apim.identity.0.principal_id

  secret_permissions = [
    "get"
  ]

  certificate_permissions = [
    "get",
    "list"
  ]
}

# Run script to apply host configuration, which is only possible when APIM managed identity has access to Key Vault certificate store
resource "null_resource" "apimManagementHostConfiguration" {
  provisioner "local-exec" {
    command = "./scripts/SetApimHostConfiguration.ps1 -resourceGroupName ${azurerm_resource_group.rg.name} -apimServiceName ${azurerm_api_management.apim.name} -apiProxyHostname ${var.apimProxyHostConfig.hostName} -kvCertificateSecret ${azurerm_key_vault_certificate.kvCertificate.secret_id}"
    interpreter = ["PowerShell", "-Command"]
  }
  depends_on = [azurerm_api_management.apim, azurerm_key_vault_access_policy.kvApimPolicy]
}

# --- Products section --
# Create Product for APIM management
resource "azurerm_api_management_product" "product" {
  product_id            = var.product.productId
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = azurerm_resource_group.rg.name
  display_name          = var.product.productName
  subscription_required = var.product.subscriptionRequired
  subscriptions_limit   = var.product.subscriptionsLimit
  approval_required     = var.product.approvalRequired
  published             = var.product.published
}
# Set product policy
resource "azurerm_api_management_product_policy" "productPolicy" {
  product_id          = var.product.productId
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content = <<XML
    <policies>
      <inbound>
        <base />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <set-header name="Server" exists-action="delete" />
        <set-header name="X-Powered-By" exists-action="delete" />
        <set-header name="X-AspNet-Version" exists-action="delete" />
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
  depends_on = [azurerm_api_management_product.product]
}

# --- Users section --
# Create Users
resource "azurerm_api_management_user" "user" {
  user_id             = "${var.product.productId}-user"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  first_name          = "User"
  last_name           = var.product.productName
  email               = "${var.product.productId}-${var.environment}@yourcompany.nl"
  state               = "active"
}

# --- Subscriptions section --
# Create Subscriptions
resource "azurerm_api_management_subscription" "subscription" {
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  product_id          = azurerm_api_management_product.product.id
  user_id             = azurerm_api_management_user.user.id
  display_name        = "Some subscription"
  state               = "active"
}

# --- Set fixed Subscription key to allow multi-region on Standard tier ---
# This is not supported out of the box, so use a powershell command (Set-AzApiManagementSubscription)
resource "null_resource" "apimSubscriptionKey" {
  triggers = {lastRunTimestamp = timestamp()}
  provisioner "local-exec" {
    command = "./scripts/SetApimSubscriptionKey.ps1 -resourceGroupName ${azurerm_resource_group.rg.name} -apimServiceName ${azurerm_api_management.apim.name} -productId ${var.product.productId} -userId ${azurerm_api_management_user.user.user_id} -subscriptionKey ${var.product.subscriptionKey} -adminUserEmail ${var.apimPublisherEmail} -adminSubscriptionKey ${var.product.adminSubscriptionKey}"
    interpreter = ["PowerShell", "-Command"]
  }
  depends_on = [azurerm_api_management_subscription.subscription]
}

# --- Diagnostics section --
# Create Application Insights
resource "azurerm_application_insights" "ai" {
  name                = local.appInsightsName
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  tags                = var.tags
}
# Create Logger
resource "azurerm_api_management_logger" "apimLogger" {
  name                = "${local.apimName}-logger"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name

  application_insights {
    instrumentation_key = azurerm_application_insights.ai.instrumentation_key
  }
}

# --- Default API for health checks ---
# Create API
resource "azurerm_api_management_api" "apiHealthProbe" {
name                = "health-probe"
resource_group_name = azurerm_resource_group.rg.name
api_management_name = azurerm_api_management.apim.name
revision            = "1"
display_name        = "Health probe"
path                = "health-probe"
protocols           = ["https"]

  subscription_key_parameter_names  {
    header = "SubscriptionKey"
    query = "SubscriptionKey"
  }

  import {
    content_format = "swagger-json"
    content_value  = <<JSON
      {
          "swagger": "2.0",
          "info": {
              "version": "1.0.0",
              "title": "Health probe"
          },
          "host": "not-used-direct-response",
          "basePath": "/",
          "schemes": [
              "https"
          ],
          "consumes": [
              "application/json"
          ],
          "produces": [
              "application/json"
          ],
          "paths": {
              "/": {
                  "get": {
                      "operationId": "get-ping",
                      "responses": {}
                  }
              }
          }
      }
    JSON
  }
}
# set api level policy
resource "azurerm_api_management_api_policy" "apiHealthProbePolicy" {
  api_name            = azurerm_api_management_api.apiHealthProbe.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name

  xml_content = <<XML
    <policies>
      <inbound>
        <return-response>
            <set-status code="200" />
        </return-response>
        <base />
      </inbound>
    </policies>
  XML
}
# Assign API to Management product in APIM
resource "azurerm_api_management_product_api" "apiProduct" {
  api_name            = azurerm_api_management_api.apiHealthProbe.name
  product_id          = azurerm_api_management_product.product.product_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
}
