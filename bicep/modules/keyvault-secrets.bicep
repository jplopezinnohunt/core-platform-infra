@description('The name of the Key Vault')
param keyVaultName string

@secure()
param sapHostname string
@secure()
param sapSystemNumber string
@secure()
param sapClient string
@secure()
param sapSystemAccountUsername string
@secure()
param sapSystemAccountPassword string

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

resource sapHostnameSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'SAP-Hostname'
  properties: {
    value: sapHostname
  }
}

resource sapSystemNumberSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'SAP-SystemNumber'
  properties: {
    value: sapSystemNumber
  }
}

resource sapClientSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'SAP-Client'
  properties: {
    value: sapClient
  }
}

resource sapUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'SAP-SystemAccount-Username'
  properties: {
    value: sapSystemAccountUsername
  }
}

resource sapPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'SAP-SystemAccount-Password'
  properties: {
    value: sapSystemAccountPassword
  }
}
