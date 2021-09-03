# Specify location to store tfstate files
terraform {
  backend "local" {
  }
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.72"
    }
  }
  required_version = ">= 1.0"
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

# Constructed names of resources
locals {
  resourceGroupName     = "${var.prefix}-blog-servicebus-${var.environment}-${var.region}"
  apimResourceGroupName = "${var.prefix}-core-${var.environment}-${var.region}"
  apimName              = "${var.prefix}-core-apim-${var.environment}-${var.region}"
}

# --- Get reference to existing APIM instance ---
data "azurerm_api_management" "apim" {
  name                = local.apimName
  resource_group_name = local.apimResourceGroupName
}

# Create a new resource group
resource "azurerm_resource_group" "rg" {
  name     = local.resourceGroupName
  location = var.location
  tags     = var.tags
}

# Create service bus namespace
resource "azurerm_servicebus_namespace" "sb" {
  name                = "didago-processing"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
}

# Create SAS policy
resource "azurerm_servicebus_namespace_authorization_rule" "authRule" {
  name                = "messagebus-policy"
  resource_group_name = azurerm_resource_group.rg.name
  namespace_name      = azurerm_servicebus_namespace.sb.name
  listen              = true
  send                = true
  manage              = true
}

# Create orders topic on service bus
resource "azurerm_servicebus_topic" "sbOrdersTopic" {
  name                = "orders"
  resource_group_name = azurerm_resource_group.rg.name
  namespace_name      = azurerm_servicebus_namespace.sb.name

  enable_partitioning = true
}

# Create customers topic on service bus
resource "azurerm_servicebus_topic" "sbCustomersTopic" {
  name                = "customers"
  resource_group_name = azurerm_resource_group.rg.name
  namespace_name      = azurerm_servicebus_namespace.sb.name

  enable_partitioning = true
}

# Create orders subscription on topic
resource "azurerm_servicebus_subscription" "sbOrdersSubscription" {
  name                = "orders"
  resource_group_name = azurerm_resource_group.rg.name
  namespace_name      = azurerm_servicebus_namespace.sb.name
  topic_name          = azurerm_servicebus_topic.sbOrdersTopic.name
  max_delivery_count  = 1
}

# Create customers subscription on topic
resource "azurerm_servicebus_subscription" "sbCustomersSubscription" {
  name                = "customers"
  resource_group_name = azurerm_resource_group.rg.name
  namespace_name      = azurerm_servicebus_namespace.sb.name
  topic_name          = azurerm_servicebus_topic.sbCustomersTopic.name
  max_delivery_count  = 1
}

# Generate SAS token to be used in the APIM policy
data "external" "generate-servicebus-sas" {
  program = ["Powershell.exe", "Set-ExecutionPolicy Bypass -Scope Process -Force; ./GenerateServiceBusSAS.ps1"]

  query = {
    servicebusUri = "${azurerm_servicebus_namespace.sb.name}.servicebus.windows.net"
    sbName        = azurerm_servicebus_namespace.sb.name
    policyName    = azurerm_servicebus_namespace_authorization_rule.authRule.name
    policyKey     = azurerm_servicebus_namespace_authorization_rule.authRule.primary_key
    sasExpiresInSeconds = 5256000
  }
}

# Add endpoints to APIM
resource "azurerm_api_management_api" "apiEndpoint" {
  name                = "${azurerm_servicebus_namespace.sb.name}-sb"
  resource_group_name = data.azurerm_api_management.apim.resource_group_name
  api_management_name = data.azurerm_api_management.apim.name
  display_name        = "messagebus"
  revision            = 1
  path                = "messagebus"
  service_url         = "https://${azurerm_servicebus_namespace.sb.name}.servicebus.windows.net"
  protocols           = ["https"]

  import {
    content_format = "openapi+json"
    content_value  = <<JSON
    {
      "openapi": "3.0.1",
      "info": {
          "title": "apim to servicebus",
          "description": "",
          "version": "1.0"
      },
      "servers": [
          {
              "url": "${data.azurerm_api_management.apim.gateway_url}/messagebus"
          }
      ],
      "paths": {
          "/orders": {
              "get": {
                  "summary": "from ${azurerm_servicebus_subscription.sbOrdersSubscription.name} subscription",
                  "operationId": "${azurerm_servicebus_subscription.sbOrdersSubscription.name}-subscription",
                  "responses": {
                      "200": {
                          "description": null
                      }
                  }
              },
              "post": {
                  "summary": "to ${azurerm_servicebus_topic.sbOrdersTopic.name}",
                  "operationId": "post-to-${azurerm_servicebus_topic.sbOrdersTopic.name}",
                  "responses": {
                      "200": {
                          "description": null
                      }
                  }
              }
          },
          "/customers": {
              "get": {
                  "summary": "from ${azurerm_servicebus_subscription.sbCustomersSubscription.name} subscription",
                  "operationId": "${azurerm_servicebus_subscription.sbCustomersSubscription.name}-subscription",
                  "responses": {
                      "200": {
                          "description": null
                      }
                  }
              },
              "post": {
                  "summary": "to ${azurerm_servicebus_topic.sbCustomersTopic.name}",
                  "operationId": "post-to-${azurerm_servicebus_topic.sbCustomersTopic.name}",
                  "responses": {
                      "200": {
                          "description": null
                      }
                  }
              }
          }
      },
      "components": {
          "securitySchemes": {
              "apiKeyHeader": {
                  "type": "apiKey",
                  "name": "Ocp-Apim-Subscription-Key",
                  "in": "header"
              },
              "apiKeyQuery": {
                  "type": "apiKey",
                  "name": "subscription-key",
                  "in": "query"
              }
          }
      },
      "security": [
          {
              "apiKeyHeader": []
          },
          {
              "apiKeyQuery": []
          }
      ]
    }
    JSON
  }
}

# Apply authentication policy to endpoints
resource "azurerm_api_management_api_policy" "apiPolicy" {
  api_name            = azurerm_api_management_api.apiEndpoint.name
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = local.apimResourceGroupName

  xml_content = <<XML
    <policies>
        <inbound>
            <base />
            <set-header name="Content-Type" exists-action="override">
                <value>application/atom+xml;type=entry;charset=utf-8</value>
            </set-header>
            <set-header name="Authorization" exists-action="override">
                <value>@((string)"${data.external.generate-servicebus-sas.result.sas}")</value>
            </set-header>
        </inbound>
        <backend>
            <forward-request />
        </backend>
        <outbound>
            <base />
        </outbound>
        <on-error>
            <base />
        </on-error>
    </policies>
  XML
}

# Apply url rewrite policy to operations, to forward the message to the correct topic
resource "azurerm_api_management_api_operation_policy" "operationPolicyOrdersPost" {
  api_name            = azurerm_api_management_api.apiEndpoint.name
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = local.apimResourceGroupName
  operation_id        = "post-to-${azurerm_servicebus_topic.sbOrdersTopic.name}"

  xml_content = <<XML
    <policies>
        <inbound>
            <base />
            <rewrite-uri template="/${azurerm_servicebus_topic.sbOrdersTopic.name}/messages" />
        </inbound>
        <backend>
            <forward-request />
        </backend>
        <outbound>
            <base />
        </outbound>
        <on-error>
            <base />
        </on-error>
    </policies>
  XML
}
resource "azurerm_api_management_api_operation_policy" "operationPolicyOrdersGet" {
  api_name            = azurerm_api_management_api.apiEndpoint.name
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = local.apimResourceGroupName
  operation_id        = "${azurerm_servicebus_subscription.sbOrdersSubscription.name}-subscription"

  xml_content = <<XML
    <policies>
        <inbound>
            <base />
            <set-method>DELETE</set-method>
            <rewrite-uri template="/${azurerm_servicebus_topic.sbOrdersTopic.name}/subscriptions/${azurerm_servicebus_subscription.sbOrdersSubscription.name}/messages/head" />
        </inbound>
        <backend>
            <forward-request />
        </backend>
        <outbound>
            <base />
        </outbound>
        <on-error>
            <base />
        </on-error>
    </policies>
  XML
}
resource "azurerm_api_management_api_operation_policy" "operationPolicyCustomersPost" {
  api_name            = azurerm_api_management_api.apiEndpoint.name
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = local.apimResourceGroupName
  operation_id        = "post-to-${azurerm_servicebus_topic.sbCustomersTopic.name}"

  xml_content = <<XML
    <policies>
        <inbound>
            <base />
            <rewrite-uri template="/${azurerm_servicebus_topic.sbCustomersTopic.name}/messages" />
        </inbound>
        <backend>
            <forward-request />
        </backend>
        <outbound>
            <base />
        </outbound>
        <on-error>
            <base />
        </on-error>
    </policies>
  XML
}
resource "azurerm_api_management_api_operation_policy" "operationPolicyCustomersGet" {
  api_name            = azurerm_api_management_api.apiEndpoint.name
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = local.apimResourceGroupName
  operation_id        = "${azurerm_servicebus_subscription.sbCustomersSubscription.name}-subscription"

  xml_content = <<XML
    <policies>
        <inbound>
            <base />
            <set-method>DELETE</set-method>
            <rewrite-uri template="/${azurerm_servicebus_topic.sbCustomersTopic.name}/subscriptions/${azurerm_servicebus_subscription.sbCustomersSubscription.name}/messages/head" />
        </inbound>
        <backend>
            <forward-request />
        </backend>
        <outbound>
            <base />
        </outbound>
        <on-error>
            <base />
        </on-error>
    </policies>
  XML
}