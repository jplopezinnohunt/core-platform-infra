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

// Reference existing Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: 'mdmportal-ca-env-dev'
}

// Reference existing Container App (API)
resource apiContainerApp 'Microsoft.App/containerApps@2023-05-01' existing = {
  name: 'vendor-mdm-api-dev'
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyVaultDeploy'
  params: {
    environmentName: environmentName
    location: location
  }
}

// Role Assignments
// Assign Container App Managed Identity access to Cosmos
module cosmosRbac 'modules/cosmos-rbac.bicep' = {
  name: 'cosmosRbacDeploy'
  params: {
    cosmosAccountName: cosmos.outputs.cosmosAccountName
    principalId: apiContainerApp.identity.principalId
  }
}

// Assign Container App Managed Identity access to Key Vault
module keyVaultRbac 'modules/keyvault-rbac.bicep' = {
  name: 'keyVaultRbacDeploy'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    keyVaultResourceId: keyVault.outputs.keyVaultResourceId
    functionAppPrincipalId: apiContainerApp.identity.principalId
  }
}
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

output containerAppName string = apiContainerApp.name
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output serviceBusNamespaceName string = serviceBus.outputs.serviceBusNamespaceName
output sapVendorCreateQueueName string = serviceBus.outputs.sapVendorCreateQueueName
