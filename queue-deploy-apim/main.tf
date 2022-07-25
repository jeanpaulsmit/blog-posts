# Specify location to store tfstate files
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "= 3.15"
    }
    azapi = {
      source  = "Azure/azapi"
    }
  }
  required_version = "= 1.2.5"
}

provider "azurerm" {
  features {}
}
provider "azapi" {
}

# Reference to the environment
data "azurerm_client_config" "current" {}

# Reference to API Management
data "azurerm_api_management" "apim" {
  name                = "didago-apim"
  resource_group_name = "didago-apim-rg"
}

# Create resource group for the storage account
resource "azurerm_resource_group" "queue-rg" {
  name = "didago-queue-rg"
  location = "westeurope"
}

# Create storage account
resource "azurerm_storage_account" "sa" {
  name                     = "didagosaqueue"
  resource_group_name      = azurerm_resource_group.queue-rg.name
  location                 = azurerm_resource_group.queue-rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create the queue
resource "azurerm_storage_queue" "queue" {
  name                 = "message-processing"
  storage_account_name = azurerm_storage_account.sa.name
}

# Assign Storage Queue Data Message Sender permissions to API management resource
resource "azurerm_role_assignment" "assign-send-permissions" {
  scope                = azurerm_storage_account.sa.id 
  role_definition_name = "Storage Queue Data Message Sender"
  principal_id         = data.azurerm_api_management.apim.identity[0].principal_id
}

# Deny access to any other resource than API management
resource "azapi_update_resource" "secure-sa" {
  type        = "Microsoft.Storage/storageAccounts@2021-09-01"
  resource_id = azurerm_storage_account.sa.id

  body = jsonencode({
    properties = {
      networkAcls = {
      defaultAction = "Deny"
      resourceAccessRules = [{
        resourceId = data.azurerm_api_management.apim.id
        tenantId   = data.azurerm_client_config.current.tenant_id
      }]
      }
    }
  })
}

# Create API in API management
resource "azurerm_api_management_api" "api" {
  name                = "queue-api"
  resource_group_name = data.azurerm_api_management.apim.resource_group_name
  api_management_name = data.azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Queue API"
  path                = "queue"
  protocols           = ["https"]
  service_url         = "${azurerm_storage_account.sa.primary_queue_endpoint}${azurerm_storage_queue.queue.name}"
}

# Add operation to API
resource "azurerm_api_management_api_operation" "operation" {
  operation_id        = "post-message"
  api_name            = azurerm_api_management_api.api.name
  api_management_name = azurerm_api_management_api.api.api_management_name
  resource_group_name = data.azurerm_api_management.apim.resource_group_name
  display_name        = "Post Message"
  method              = "POST"
  url_template        = "/messages"
  description         = "Post message to backend queue"

  response {
    status_code = 202
  }
}

# Configure policy on operation
resource "azurerm_api_management_api_operation_policy" "policy" {
  api_name            = azurerm_api_management_api_operation.operation.api_name
  api_management_name = azurerm_api_management_api_operation.operation.api_management_name
  resource_group_name = azurerm_api_management_api_operation.operation.resource_group_name
  operation_id        = azurerm_api_management_api_operation.operation.operation_id

  xml_content = <<XML
  <policies>
      <inbound>
          <base />
          <set-header name="x-ms-version" exists-action="override">
              <value>2021-08-06</value>
          </set-header>
          <authentication-managed-identity resource="https://storage.azure.com/" />
          <set-header name="content-type" exists-action="override">
              <value>application/xml</value>
          </set-header>
          <set-body>@{
                  return "<QueueMessage><MessageText>" + context.Request.Body.As<string>() + "</MessageText></QueueMessage>";
              }</set-body>
          <rewrite-uri template="/messages" copy-unmatched-params="true" />
      </inbound>
      <backend>
          <forward-request />
      </backend>
      <outbound>
          <return-response>
              <set-status code="202" />
          </return-response>
          <base />
      </outbound>
      <on-error>
          <base />
      </on-error>
  </policies>
XML
}
