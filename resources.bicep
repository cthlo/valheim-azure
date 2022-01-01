// Valheim
param valheim_world string = 'HelloWorld'
@secure()
param valheim_server_password string

// VM
param virtualMachine_name string = 'valheim-server'
param virtualMachine_adminUserName string = 'azureuser'
@secure()
param virtualMachine_sshPublicKey string = ''

// Networking
param publicIPAddress_name string = 'valheim-server-ip'
param virtualNetwork_name string = 'valheim-vnet'
param networkSecurityGroup_name string = 'valheim-server-nsg'
param networkSecurityGroup_sshAcceptedSources array = [] // default: deny all sources
param networkSecurityGroup_valheimAcceptedSources array = [] // default: allow all sources
param networkInterface_name string = 'valheim-server-nic'

resource virtualMachines_valheim_server_name_resource 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: virtualMachine_name
  location: resourceGroup().location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B4ms'
    }
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        osType: 'Linux'
        name: '${virtualMachine_name}_osDisk'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        deleteOption: 'Detach'
      }
    }
    osProfile: {
      computerName: virtualMachine_name
      adminUsername: virtualMachine_adminUserName
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: empty(virtualMachine_sshPublicKey) ? null : {
          publicKeys: [
            {
              path: '/home/${virtualMachine_adminUserName}/.ssh/authorized_keys'
              keyData: virtualMachine_sshPublicKey
            }
          ]
        }
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
      }
      customData: base64(replace(replace(loadTextContent('cloud-init.cfg'), '{{VALHEIM_SERVER_PASSWORD}}', '${valheim_server_password}'), '{{VALHEIM_WORLD}}', '${valheim_world}'))
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: publicIPAddress_name
  location: resourceGroup().location
  sku: {
    name: 'Basic'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Dynamic'
    idleTimeoutInMinutes: 4
  }
}

var subnet_name = 'default'
var subnet_properties = {
  addressPrefix: '10.0.0.0/24'
  delegations: []
  privateEndpointNetworkPolicies: 'Enabled'
  privateLinkServiceNetworkPolicies: 'Enabled'
}
resource virtualNetwork_subnet_default 'Microsoft.Network/virtualNetworks/subnets@2021-05-01' = {
  parent: virtualNetwork
  name: subnet_name
  properties: subnet_properties
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: virtualNetwork_name
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnet_name
        properties: subnet_properties
      }
    ]
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: networkSecurityGroup_name
  location: resourceGroup().location
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: empty(networkSecurityGroup_sshAcceptedSources) ? '*' : null
          sourceAddressPrefixes: empty(networkSecurityGroup_sshAcceptedSources) ? null : networkSecurityGroup_sshAcceptedSources
          destinationAddressPrefix: '*'
          access: empty(networkSecurityGroup_sshAcceptedSources) ? 'Deny' : 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'ValheimServer'
        properties: {
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRange: '2456'
          sourceAddressPrefix: empty(networkSecurityGroup_valheimAcceptedSources) ? '*' : null
          sourceAddressPrefixes: empty(networkSecurityGroup_valheimAcceptedSources) ? null : networkSecurityGroup_valheimAcceptedSources
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: networkInterface_name
  location: resourceGroup().location
  properties: {
    ipConfigurations: [
      {
        name: 'primary'
        properties: {
          privateIPAddress: '10.0.0.4'
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
          subnet: {
            id: virtualNetwork_subnet_default.id
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
    dnsSettings: {
      dnsServers: []
    }
    enableAcceleratedNetworking: false
    enableIPForwarding: false
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

