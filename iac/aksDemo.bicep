// Parameters
param roleDefinitionId string = 'b24988ac-6180-42a0-ab88-20f7382dd24c' //Default as contributor role
param sqlServerAdministratorLogin string = ''
param k8sversion string = '1.21.2'
param pgVersion string = '10'

param agentCount int = 3
param osDiskSizeGB int = 128
param location string = 'eastus2'
param agentVMSize string = 'Standard_A2_v2'
param servicePrincipalClientId string = 'msi'

@secure()
param sqlServerAdministratorPassword string = ''

// Variables
var identity_name = 'ttmanagedidentity-${uniqueString(resourceGroup().id)}'
var acr_name = 'ttacr${uniqueString(resourceGroup().id)}'
var storage_name = toLower('ttstorage${uniqueString(resourceGroup().id)}')
var keyvault_name = 'ttkeyvault${uniqueString(resourceGroup().id)}'
var aks_name = 'tailwindtradersaks${uniqueString(resourceGroup().id)}'
var function_name = 'ttfunction${uniqueString(resourceGroup().id)}'
var sqlserver_name = 'ttsqlserver${uniqueString(resourceGroup().id)}'
var pg_name = 'ttpg${uniqueString(resourceGroup().id)}'
var coupons_cosmosdb_name = 'ttcouponsdb${uniqueString(resourceGroup().id)}'
var shopping_cosmosdb_name = 'ttshoppingdb${uniqueString(resourceGroup().id)}'
var components_app_insights_name = 'tt-app-insights'
var dnsPrefix = '${aks_name}-dns'
var workspace_name = 'ttoms${uniqueString(resourceGroup().id)}'
var acrVersion = '2019-05-01'

// Create Keyvault
resource keyvault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: keyvault_name
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [ 
      {
        tenantId: subscription().tenantId
        objectId: msi.properties.principalId
        permissions: {
          keys: ['all'
          ]
          secrets: ['all'
          ]
          certificates: ['all'
          ]
          storage: ['all'
          ]
        }
      }
    ]
    publicNetworkAccess: 'Enabled'
  }
}

// Create Managed Identity
resource msi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identity_name
  location: location
}

// Create Role Assignment for MSI
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2018-09-01-preview' = {
  name: guid(roleDefinitionId, resourceGroup().id)
  dependsOn: [
    msi
  ]
  properties: {
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: msi.properties.principalId
  }
}

// Create OMS Workspace for Container Insights
resource omsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01'= {
  name: workspace_name
  location: location
  properties: {
    sku: {
      name: 'Standard'
    }
    retentionInDays: 30
  }
}

// Create App Insights
resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: components_app_insights_name
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    Request_Source: 'rest'
  }
}

// Create Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' = {
  name: acr_name
  dependsOn: [
    roleAssignment
  ]
  location: location
  sku: {
    name: 'Premium'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${msi.id}': {}
    }
  }
  properties: {
    adminUserEnabled: true
  }
}

// Create Azure Storage
resource storage 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storage_name// must be globally unique
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: false
  }
}

// Create AKS
resource aks 'Microsoft.ContainerService/managedClusters@2020-09-01' = {
  name: aks_name
  dependsOn: [
    roleAssignment
    omsWorkspace
  ]
  location: location
  sku: {
    name: 'Basic'
    tier: 'Free'
  }
  properties: {
    kubernetesVersion: k8sversion
    enableRBAC: true
    dnsPrefix: dnsPrefix
    addonProfiles: {
      httpApplicationRouting: {
        enabled: true
      }
      azurePolicy: {
        enabled: false
      }
      omsAgent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceId: omsWorkspace.id
        }
      }
    }
    agentPoolProfiles: [
      {
        name: 'agentpool'
        osDiskSizeGB: osDiskSizeGB
        count: agentCount
        vmSize: agentVMSize
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        maxPods: 110
        availabilityZones: [
          '1'
        ]
      }
    ]
    networkProfile: {
      loadBalancerSku: 'standard'
      networkPlugin: 'kubenet'
    }
    apiServerAccessProfile: {
      enablePrivateCluster: false
    }
    servicePrincipalProfile: {
      clientId: servicePrincipalClientId
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${msi.id}': {}
    }
  }
}

// Create Functions App
resource functionApp 'Microsoft.Web/sites@2021-01-15' = {
  name: function_name
  kind: 'functionapp'
  location: location
  properties: {
    enabled: true
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'AzureWebJobsStorage'
          value: concat('DefaultEndpointsProtocol=https;AccountName=',storage_name,';AccountKey=',listKeys(resourceId('Microsoft.Storage/storageAccounts', storage_name), '2015-05-01-preview').key1)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~2'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: concat('DefaultEndpointsProtocol=https;AccountName=',storage_name,';AccountKey=',listKeys(resourceId('Microsoft.Storage/storageAccounts', storage_name), '2015-05-01-preview').key1)
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '8.11.1'
        }
      ]
    }
    clientAffinityEnabled: false
    reserved: false
  }
  dependsOn: [
    storage
  ]
}

// Create PostgresSQL Server, DB, and Firewall Rules
resource pgDatabase 'Microsoft.DBforPostgreSQL/servers@2017-12-01' = {
  name: pg_name
  location: location
  properties: {
    createMode: 'Default'
    version: pgVersion
    administratorLogin: sqlServerAdministratorLogin
    administratorLoginPassword: sqlServerAdministratorPassword
    storageProfile: {
      storageMB: 5120
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
  }
  sku: {
    name: 'GP_Gen5_2'
    tier: 'GeneralPurpose'
    capacity: 2
    size: '5120'
    family: 'Gen5'
  }
  resource stockPgDb 'databases' = {
    name: 'stockdb'
    dependsOn: [
      pgDatabase
    ]
  }
  resource pgDBFirewallRules 'firewallRules' = {
    name: 'AllowAllAzureIps'
    properties: {
      endIpAddress: '0.0.0.0'
      startIpAddress: '0.0.0.0'
    }
  }
}

// Create SQL Servers, DBs, and firewall rules
resource sqlServer 'Microsoft.Sql/servers@2021-02-01-preview' = {
  name: sqlserver_name
  location: location
  properties: {
    administratorLogin: sqlServerAdministratorLogin
    administratorLoginPassword: sqlServerAdministratorPassword
  }
  resource productsDb 'databases' = {
    name: 'Products'
    dependsOn: [
      sqlServer
    ]
    sku: {
      name: 'S0'
      tier: 'Standard'
    }
    location: location
    properties: { 
      collation: 'SQL_Latin1_General_CP1_CI_AS'
      maxSizeBytes: 268435456000
      sampleName: null
      zoneRedundant: false
      licenseType: null
    }
  }
  resource profilesDb 'databases' = {
    name: 'Profiles'
    dependsOn: [
      sqlServer
    ]
    sku: {
      name: 'S0'
      tier: 'Standard'
    }
    location: location
    properties: { 
      collation: 'SQL_Latin1_General_CP1_CI_AS'
      maxSizeBytes: 268435456000
      sampleName: null
      zoneRedundant: false
      licenseType: null
    }
  }
  resource popularProductsDb 'databases' = {
    name: 'PopularProducts'
    dependsOn: [
      sqlServer
    ]
    sku: {
      name: 'S0'
      tier: 'Standard'
    }
    location: location
    properties: { 
      collation: 'SQL_Latin1_General_CP1_CI_AS'
      maxSizeBytes: 268435456000
      sampleName: null
      zoneRedundant: false
      licenseType: null
    }
  }
  resource firewallRules 'firewallrules' = {
    name: 'AllowAllWindowsAzureIps'
    dependsOn: [
      sqlServer
    ]
    properties: {
      endIpAddress: '255.255.255.255'
      startIpAddress: '0.0.0.0'
    }
  }
  resource securityAlertPolicies 'securityAlertPolicies' = {
    name: 'Default'
    dependsOn: [
      sqlServer
    ]
    properties: {
      state: 'Enabled'
      disabledAlerts: [
        
      ]
      emailAddresses: [
        
      ]
      emailAccountAdmins: true
    }
  }
}

// Create Documents DB
resource documentDb 'Microsoft.DocumentDB/databaseAccounts@2021-06-15' = {
  name: shopping_cosmosdb_name
  kind: 'GlobalDocumentDB'
  location: location
  tags: {
    defaultExperience: 'Core (SQL)'
  }
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        // id: '${shopping_cosmosdb_name}-${resourceGroup().location}'
        failoverPriority: 0
        locationName: resourceGroup().location
      }
    ]
    enableMultipleWriteLocations: true
    isVirtualNetworkFilterEnabled: false
    virtualNetworkRules: [
      
    ]
  }
}

// Create MongoDB
resource mongoDb 'Microsoft.DocumentDB/databaseAccounts@2021-06-15' = {
  name: coupons_cosmosdb_name
  kind: 'MongoDB'
  location: location
  tags: {
    defaultExperience: 'Azure Cosmos DB for MongoDB API'
  }
  properties: {
    databaseAccountOfferType: 'Standard'
    locations:  [
      {
        // id: '${coupons_cosmosdb_name}-${resourceGroup().location}'
        failoverPriority: 0
        locationName: resourceGroup().location
      }
    ]
    enableMultipleWriteLocations: true
    isVirtualNetworkFilterEnabled: false
    virtualNetworkRules: [
      
    ]
  }
}

// outputs
output acrAdminName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output acrPass string = listCredentials(acr.id, acrVersion).passwords[0].value
output InstrumentationKey string = insights.properties.InstrumentationKey
output aksClusterName string = aks_name
output sqlServerName string = sqlserver_name
output couponsDB string = coupons_cosmosdb_name
output shoppingDB string = shopping_cosmosdb_name
output keyVaultUri string = keyvault.properties.vaultUri
output keyVaultId string = keyvault.id
output workspace_id string = omsWorkspace.id
output workspace_name string = omsWorkspace.name

// output storageAccountName string = stgName
// output cognitiveServiceKey string = listkeys(cognitiveServicesId, csApiVersion).key1
// output storageAccountKey string = listKeys(storageAccountId, stgApiVersion).keys[0].value
// output cognitiveServiceEndpoint string = reference(cognitiveServicesId, csApiVersion).endpoint
// output serviceBusEndpoint string = listkeys(authRuleResourceId, sbApiVersion).primaryConnectionString
