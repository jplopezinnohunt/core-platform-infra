@description('The environment name (dev, qa, prod)')
param environmentName string

@description('The Azure region')
param location string

var accountName = 'mdmportal-cosmos-${environmentName}'
var databaseName = 'VendorMdm'

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: accountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
  }
}

resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource containerChangeRequest 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDb
  name: 'ChangeRequestData'
  properties: {
    resource: {
      id: 'ChangeRequestData'
      partitionKey: {
        paths: [
          '/requestId'
        ]
        kind: 'Hash'
      }
    }
    options: {
      throughput: 400
    }
  }
}

resource containerDomainEvents 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDb
  name: 'DomainEvents'
  properties: {
    resource: {
      id: 'DomainEvents'
      partitionKey: {
        paths: [
          '/eventType'
        ]
        kind: 'Hash'
      }
    }
    options: {
      throughput: 400
    }
  }
}

resource containerReferenceData 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDb
  name: 'ReferenceData'
  properties: {
    resource: {
      id: 'ReferenceData'
      partitionKey: {
        paths: [
          '/category'
        ]
        kind: 'Hash'
      }
    }
    options: {
      throughput: 400
    }
  }
}

resource containerValidationRules 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDb
  name: 'ValidationRules'
  properties: {
    resource: {
      id: 'ValidationRules'
      partitionKey: {
        paths: [
          '/entityType'
        ]
        kind: 'Hash'
      }
    }
    options: {
      throughput: 400
    }
  }
}

// Container for Invitation Artifacts (follows hybrid architecture pattern)
resource containerInvitationArtifacts 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDb
  name: 'InvitationArtifacts'
  properties: {
    resource: {
      id: 'InvitationArtifacts'
      partitionKey: {
        paths: [
          '/invitationId'
        ]
        kind: 'Hash'
      }
    }
    options: {
      throughput: 400
    }
  }
}

output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
