@description('The environment name (dev, qa, prod)')
// Trigger deployment
param environmentName string = 'dev'

@description('The Azure region for compute/platform resources')
param location string = 'eastus'

@description('The Azure region for data resources (Cosmos DB, SQL)')
param dataLocation string = 'eastus2'

@secure()
@description('SQL Server administrator login')
param sqlAdminLogin string = 'mdmadmin'

@secure()
@description('SQL Server administrator password')
param sqlAdminPassword string

@secure()
@description('SAP system account username')
param sapSystemAccountUsername string = 'SAPVENDORPORTAL'

@secure()
@description('SAP system account password')
param sapSystemAccountPassword string

@description('SAP hostname')
param sapHostname string = 'sap-dev.company.com'

@description('SAP system number')
param sapSystemNumber string = '00'

@description('SAP client')
param sapClient string = '100'

module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmosDeploy'
  params: {
    environmentName: environmentName
    location: dataLocation
  }
}

module sql 'modules/sql.bicep' = {
  name: 'sqlDeploy'
  params: {
    environmentName: environmentName
    location: dataLocation
    adminLogin: sqlAdminLogin
    adminPassword: sqlAdminPassword
  }
}

module serviceBus 'modules/servicebus.bicep' = {
  name: 'serviceBusDeploy'
  params: {
    environmentName: environmentName
    location: location
  }
}

// Shared App Service Plan for both Web App and Function App (saves quota)
resource sharedAppServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'asp-core-platform-${environmentName}'
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {}
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyVaultDeploy'
  params: {
    environmentName: environmentName
    location: location
  }
}

module functionApp 'modules/functionapp.bicep' = {
  name: 'functionAppDeploy'
  params: {
    environmentName: environmentName
    location: location
    appServicePlanId: sharedAppServicePlan.id
  }
}

module webApp 'modules/webapp.bicep' = {
  name: 'webAppDeploy'
  params: {
    environmentName: environmentName
    location: location
    keyVaultName: keyVault.outputs.keyVaultName
    keyVaultId: keyVault.outputs.keyVaultResourceId
    appServicePlanId: sharedAppServicePlan.id
  }
}

// Role Assignments
// Assign Function App Managed Identity access to Cosmos
module cosmosRbac 'modules/cosmos-rbac.bicep' = {
  name: 'cosmosRbacDeploy'
  params: {
    cosmosAccountName: cosmos.outputs.cosmosAccountName
    principalId: functionApp.outputs.functionAppPrincipalId
  }
}

// Assign Function App Managed Identity access to Key Vault
module keyVaultRbac 'modules/keyvault-rbac.bicep' = {
  name: 'keyVaultRbacDeploy'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    keyVaultResourceId: keyVault.outputs.keyVaultResourceId
    functionAppPrincipalId: functionApp.outputs.functionAppPrincipalId
  }
}

// Store SAP credentials in Key Vault
// Store SAP credentials in Key Vault
module keyVaultSecrets 'modules/keyvault-secrets.bicep' = {
  name: 'keyVaultSecretsDeploy'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    sapHostname: sapHostname
    sapSystemNumber: sapSystemNumber
    sapClient: sapClient
    sapSystemAccountUsername: sapSystemAccountUsername
    sapSystemAccountPassword: sapSystemAccountPassword
  }
}

output functionAppName string = functionApp.outputs.functionAppName
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output serviceBusNamespaceName string = serviceBus.outputs.serviceBusNamespaceName
output sapVendorCreateQueueName string = serviceBus.outputs.sapVendorCreateQueueName
