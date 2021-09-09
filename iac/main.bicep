targetScope = 'subscription'

param location string = 'eastus'
param k8sversion string = '1.21.2'
param rgName string = 'twtdemo'
param sqlServerAdministratorLogin string = ''

@secure()
param sqlServerAdministratorPassword string = ''

resource rg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: rgName
  location: location
}

module aksDemo './aksDemo.bicep' = {
  name: 'twtdemo'
  scope: resourceGroup(rg.name)
  params: {
     location: location
     k8sversion: k8sversion
     sqlServerAdministratorLogin: sqlServerAdministratorLogin
     sqlServerAdministratorPassword: sqlServerAdministratorPassword
  }
}

// module createKeyVaultSecrets './createSecrets.bicep' = {
//   name: 'createSecrets'
//   dependsOn: aksDemo
//   scope: resourceGroup(rg.name)
//   params: {
//     acr_server: aksDemo.outputs.acrLoginServer
//     acr_password: aksDemo.outputs.acrPass
//     sql_server_admin: 
//     sql_server_pass: 
//     acr_admin: aksDemo.outputs.acrAdminName
//   }
// }

output acr_admin_name string = aksDemo.outputs.acrAdminName
output acr_login_server string = aksDemo.outputs.acrLoginServer
output acr_password string = aksDemo.outputs.acrPass
output InstrumentationKey string = aksDemo.outputs.InstrumentationKey
output aksClusterName string = aksDemo.outputs.aksClusterName

// output storageAccountKey string = aksDemo.outputs.storageAccountKey
// output storageAccountName string = aksDemo.outputs.storageAccountName
// output serviceBusEndpoint string = aksDemo.outputs.serviceBusEndpoint
// output cognitiveServiceKey string = aksDemo.outputs.cognitiveServiceKey
// output cognitiveServiceEndpoint string = aksDemo.outputs.cognitiveServiceEndpoint
