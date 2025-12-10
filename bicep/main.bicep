@description('The environment name (dev, qa, prod)')
param environmentName string = 'dev'

@description('The Azure region')
param location string = resourceGroup().location

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

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyVaultDeploy'
  params: {
    environmentName: environmentName
    location: location
  }
}

// Role Assignments
// Assign Function App Managed Identity access to Cosmos
var cosmosAccountName = cosmos.outputs.cosmosAccountName
var roleAssignmentName = guid(cosmosAccountName, functionApp.outputs.functionAppPrincipalId, '00000000-0000-0000-0000-000000000002')

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: cosmosAccountName
}

resource cosmosRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-04-15' = {
  name: '${cosmosAccount.name}/${roleAssignmentName}'
  properties: {
    roleDefinitionId: resourceId('Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', cosmosAccountName, '00000000-0000-0000-0000-000000000002')
    principalId: functionApp.outputs.functionAppPrincipalId
    scope: cosmosAccount.id
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
resource keyVaultResource 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVault.outputs.keyVaultName
}

resource sapHostnameSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVaultResource
  name: 'SAP-Hostname'
  properties: {
    value: sapHostname
  }
}

resource sapSystemNumberSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVaultResource
  name: 'SAP-SystemNumber'
  properties: {
    value: sapSystemNumber
  }
}

resource sapClientSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVaultResource
  name: 'SAP-Client'
  properties: {
    value: sapClient
  }
}

resource sapUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVaultResource
  name: 'SAP-SystemAccount-Username'
  properties: {
    value: sapSystemAccountUsername
  }
}

resource sapPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVaultResource
  name: 'SAP-SystemAccount-Password'
  properties: {
    value: sapSystemAccountPassword
  }
}

output functionAppName string = functionApp.outputs.functionAppName
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output serviceBusNamespaceName string = serviceBus.outputs.serviceBusNamespaceName
output sapVendorCreateQueueName string = serviceBus.outputs.sapVendorCreateQueueName
