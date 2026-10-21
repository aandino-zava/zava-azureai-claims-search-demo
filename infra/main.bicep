targetScope = 'resourceGroup'

@description('Azure region for all three services and the Foundry project.')
param location string

@minLength(2)
@maxLength(60)
param searchServiceName string

@minLength(2)
@maxLength(64)
param foundryName string

@minLength(2)
@maxLength(64)
param projectName string

@minLength(3)
@maxLength(24)
param storageAccountName string

@minLength(3)
@maxLength(63)
param containerName string

@minLength(3)
@maxLength(63)
param imageOutputContainerName string

@minLength(2)
@maxLength(100)
param knowledgeSourceName string

type ModelDeployment = {
  name: string
  modelName: string
  modelVersion: string
  sku: string
  capacity: int
}

param embeddingDeployment ModelDeployment
param chatDeployment ModelDeployment

var tags = {
  managedBy: 'zava-azureai-claims-search-demo'
}

resource search 'Microsoft.Search/searchServices@2025-05-01' = {
  name: searchServiceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'standard'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    semanticSearch: 'free'
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectName
    description: 'Zava Medical Claims'
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_ZRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    allowCrossTenantReplication: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'None'
    }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  name: '${storage.name}/default/${containerName}'
  properties: {
    publicAccess: 'None'
  }
}

resource imageOutputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  name: '${storage.name}/default/${imageOutputContainerName}'
  properties: {
    publicAccess: 'None'
  }
}

resource embeddingModel 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: embeddingDeployment.name
  sku: {
    name: embeddingDeployment.sku
    capacity: embeddingDeployment.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingDeployment.modelName
      version: embeddingDeployment.modelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

resource chatModel 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: chatDeployment.name
  sku: {
    name: chatDeployment.sku
    capacity: chatDeployment.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatDeployment.modelName
      version: chatDeployment.modelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  dependsOn: [
    embeddingModel
  ]
}

resource searchBlobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, search.id, 'blob-reader')
  scope: storage
  properties: {
    principalId: search.identity!.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  }
}

resource searchModelUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, search.id, 'openai-user')
  scope: foundry
  properties: {
    principalId: search.identity!.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  }
}

output searchServiceId string = search.id
output foundryId string = foundry.id
output projectId string = project.id
output storageAccountId string = storage.id
output containerId string = container.id
output imageOutputContainerId string = imageOutputContainer.id
output knowledgeSourceEndpoint string = 'https://${search.name}.search.windows.net/knowledgesources/${knowledgeSourceName}'
