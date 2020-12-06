
// Params can be injected during deployment, typically for deploy-time values
param env string = 'dev'
param sa_sku object = { 
  name: 'Standard_LRS' 
  tier: 'Standard'
 }

// Vars can contain runtime variable values
var region = 'we'
var company = 'didago'
var saName = replace('${company}-sa-${env}-${region}', '-', '')
var apimName = '${company}-apim-${env}-${region}'
var aiName = '${company}-ai-${env}-${region}'

// Create storage account to hold API and APIM related files
resource sa 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: '${saName}'
  location: '${resourceGroup().location}'
  kind: 'StorageV2'
  sku: sa_sku
  properties:{
    supportsHttpsTrafficOnly: true
  }
}

// Link container to storage account by providing path as name
resource saContainerApim 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${sa.name}/default/apim-files'
}
resource saContainerApi 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${sa.name}/default/api-files'
}

// Output the storage account name, because we need it later in the deployment to deploy files to it
output storageAccountName string = sa.name

// Create APIM service instance
resource apim 'Microsoft.ApiManagement/service@2019-12-01' = {
  name: '${apimName}'
  location: '${resourceGroup().location}'
  sku:{
    capacity: 1
    name: 'Developer'	
  }
  identity:{
    type:'SystemAssigned'
  }
  properties:{
    publisherName: 'Didago'
    publisherEmail: 'email@address.com'
  }  
}

// Set policy on tenant level
resource apimPolicy 'Microsoft.ApiManagement/service/policies@2019-12-01' = {
  name: '${apim.name}/policy'
  properties:{
    format: 'rawxml'
    value: '<policies><inbound /><backend><forward-request /></backend><outbound /><on-error /></policies>'
  }
}

// Add AppInsights
resource ai 'Microsoft.Insights/components@2015-05-01' = {
  name: '${aiName}'
  location: '${resourceGroup().location}'
  kind: 'web'
  properties:{
    Application_Type:'web'
  }
}

// Add APIM logger and link it to AppInsights
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2019-12-01' = {
  name: '${apim.name}/${apim.name}-logger'
  properties:{
    resourceId: '${ai.id}'
    loggerType: 'applicationInsights'
    credentials:{
      instrumentationKey: '${ai.properties.InstrumentationKey}'
    }
  }
}

