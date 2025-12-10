@description('The environment name (dev, qa, prod)')
param environmentName string

@description('The Azure region')
param location string

@description('The SQL Administrator Login')
param adminLogin string = 'mdmadmin'

@secure()
@description('The SQL Administrator Password')
param adminPassword string

var serverName = 'mdmportal-sql-12031241-${environmentName}'
var dbName = 'mdmportal-sqldb-${environmentName}'

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  parent: sqlServer
  name: dbName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648 // 2 GB
  }
}

output sqlServerName string = sqlServer.name
output sqlDbName string = sqlDb.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
