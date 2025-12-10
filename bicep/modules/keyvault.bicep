@description('The environment name (dev, qa, prod)')
param environmentName string

@description('The Azure region')
param location string = resourceGroup().location

@description('Enable soft delete and purge protection')
param enableSoftDelete bool = true

@description('Enable purge protection')
param enablePurgeProtection bool = true

var keyVaultName = 'vendormdm-kv-${environmentName}-eus2'

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableSoftDelete: enableSoftDelete
    enablePurgeProtection: enablePurgeProtection
    enableRbacAuthorization: true // Use RBAC for better security and role management
    accessPolicies: [] // Empty when using RBAC
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Outputs
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultResourceId string = keyVault.id
output keyVaultId string = keyVault.id

