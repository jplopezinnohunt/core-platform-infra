@description('The environment name')
param environmentName string

@description('The Azure region')
param location string

@description('The name of the existing Key Vault to access')
param keyVaultName string

@description('The Resource ID of the existing Key Vault')
param keyVaultId string

@description('Existing App Service Plan ID to use (shared with Function App)')
param appServicePlanId string

var webAppName = 'core-apis-${environmentName}'

resource webApp 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      use32BitWorkerProcess: false
      alwaysOn: false 
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Grant Web App access to Key Vault
module keyVaultAccess 'keyvault-rbac.bicep' = {
  name: 'webAppKeyVaultAccess'
  params: {
    keyVaultName: keyVaultName
    keyVaultResourceId: keyVaultId
    functionAppPrincipalId: webApp.identity.principalId // Reusing the param name but passing WebApp ID
  }
}

output webAppName string = webApp.name
output webAppHostName string = webApp.properties.defaultHostName
output webAppPrincipalId string = webApp.identity.principalId
