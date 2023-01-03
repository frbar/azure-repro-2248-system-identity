targetScope = 'resourceGroup'

param tenantId string = subscription().tenantId

@description('The kind of the app service plan')
@allowed(['linux', 'windows'])
param kind string = 'linux'

@description('The name of the function app that you wish to create.')
param appName string = 'fnapp${uniqueString(resourceGroup().id)}-${kind == 'windows' ? 'win' : 'linux'}'

@description('Location for all resources.')
param location string = resourceGroup().location

@secure()
param demoSecretValue string = newGuid()

var functionAppName = appName
var hostingPlanName = appName
param fxVersion string = 'Node|16'
param storageAccountType string = 'Standard_LRS'
var keyVaultName = appName
var secretName = 'SecretForMyFunction'
var storageAccountName = '${uniqueString(resourceGroup().id)}azfunctions'
var functionWorkerRuntime = 'node'

resource kv 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    tenantId: tenantId
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: kv
  name: 'SecretForMyFunction'
  properties: {
    value: demoSecretValue
  }
}

resource accessPolicyForFunction 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  name: 'add'
  parent: kv
  properties: {
    accessPolicies: [
      {
        objectId: functionApp.identity.principalId
        permissions: {
          certificates: [ ]
          keys: [ ]
          secrets: [ 'Get' ]
          storage: [ ]
        }
        tenantId: tenantId
      }
    ]
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountType
  }
  kind: 'Storage'
}

resource hostingPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: hostingPlanName
  location: location
  kind: kind
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: kind == 'linux' ? true : false     // required for using linux
  }
}

resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      nodeVersion: '16'
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      linuxFxVersion: (kind == 'linux' ? fxVersion : null)
      windowsFxVersion: (kind == 'windows' ? fxVersion : null)
      netFrameworkVersion: (kind == 'windows' ? 'v6.0' : 'v4.0')
      remoteDebuggingVersion: (kind == 'windows' ? 'VS2019' : null)
    }
    httpsOnly: true
  }
}

resource symbolicname 'Microsoft.Web/sites/config@2022-03-01' = {
  name: 'appsettings'
  kind: 'string'
  parent: functionApp
  dependsOn: [ accessPolicyForFunction ]
  properties: {
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    WEBSITE_CONTENTSHARE: toLower(functionAppName)
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: functionWorkerRuntime
    WEBSITE_NODE_DEFAULT_VERSION: '~16'
    MySecret: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=${secretName})'
    MyNonSecret: uniqueString(resourceGroup().id)
  }
}

output functionName string = functionApp.name
