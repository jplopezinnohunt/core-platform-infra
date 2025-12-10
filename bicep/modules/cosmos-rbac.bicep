@description('The name of the Cosmos DB Account')
param cosmosAccountName string

@description('The Principal ID of the Function App')
param principalId string

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: cosmosAccountName
}

// Built-in Role: Cosmos DB Built-in Data Contributor
// ID: 00000000-0000-0000-0000-000000000002
var roleDefinitionId = '00000000-0000-0000-0000-000000000002'
var roleAssignmentName = guid(cosmosAccount.id, principalId, roleDefinitionId)

resource cosmosRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-04-15' = {
  parent: cosmosAccount
  name: roleAssignmentName
  properties: {
    roleDefinitionId: resourceId('Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', cosmosAccountName, roleDefinitionId)
    principalId: principalId
    scope: cosmosAccount.id
  }
}
