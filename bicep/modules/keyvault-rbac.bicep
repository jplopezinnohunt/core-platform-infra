@description('Assign RBAC roles to Key Vault')
param keyVaultName string
param keyVaultResourceId string
param userPrincipalId string = ''
param functionAppPrincipalId string = ''

// Role Definition IDs for Key Vault
// Key Vault Secrets Officer - Full control of secrets
var secretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
// Key Vault Secrets User - Read secrets
var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// Assign role to user if provided
resource userRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (userPrincipalId != '') {
  name: guid(keyVaultResourceId, userPrincipalId, secretsOfficerRoleId)
  scope: keyVaultResourceId
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsOfficerRoleId)
    principalId: userPrincipalId
    principalType: 'User'
  }
}

// Assign role to Function App Managed Identity if provided
resource functionAppRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (functionAppPrincipalId != '') {
  name: guid(keyVaultResourceId, functionAppPrincipalId, secretsUserRoleId)
  scope: keyVaultResourceId
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsUserRoleId)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output userRoleAssignmentId string = userRoleAssignment.id
output functionAppRoleAssignmentId string = functionAppRoleAssignment.id

