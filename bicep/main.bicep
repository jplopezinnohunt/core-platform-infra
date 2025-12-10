@description('The environment name (dev, qa, prod)')
// Trigger deployment
param environmentName string = 'dev'

@description('The Azure region')
param location string = 'eastus2'

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
    location: location
  }
}

module sql 'modules/sql.bicep' = {
  name: 'sqlDeploy'
  params: {
    environmentName: environmentName
    location: location
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

module functionApp 'modules/functionapp.bicep' = {
  name: 'functionAppDeploy'
  params: {
    environmentName: environmentName
    location: location
  }
}

module webApp 'modules/webapp.bicep' = {
  name: 'webAppDeploy'
  params: {
    environmentName: environmentName
    location: location
    keyVaultName: keyVault.outputs.keyVaultName
    keyVaultId: keyVault.outputs.keyVaultResourceId
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyVaultDeploy'
  params: {
    environmentName: environmentName
    location: location
  }
}

// Role Assignments
// Assign Function App Managed Identity access to Cosmos
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
