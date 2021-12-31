targetScope = 'subscription'

param resourceGroup_name string = 'valheim'
param resourceGroup_location string = 'eastus'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroup_name
  location: resourceGroup_location
}
