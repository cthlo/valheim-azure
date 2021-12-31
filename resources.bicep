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
param networkSecurityGroup_sshAcceptedSource string = '' // default: accept no SSH connection
param networkSecurityGroup_valheimAcceptedSources array = [] // default: accept all sources
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
          id: resourceId('Microsoft.Compute/disks', '${virtualMachine_name}_osDisk')
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
      customData: replace(replace(loadTextContent('cloud-init.cfg'), '{{VALHEIM_SERVER_PASSWORD}}', '${valheim_server_password}'), '{{VALHEIM_WORLD}}', '${valheim_world}')
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
        name: 'default'
        properties: {
          addressPrefix: '10.0.0.0/24'
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
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
      empty(networkSecurityGroup_sshAcceptedSource) ? {} : {
        name: 'SSH'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: networkSecurityGroup_sshAcceptedSource
          destinationAddressPrefix: '*'
          access: 'Allow'
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
          sourceAddressPrefix: empty(networkSecurityGroup_valheimAcceptedSources) ? '*' : ''
          sourceAddressPrefixes: empty(networkSecurityGroup_valheimAcceptedSources) ? [] : networkSecurityGroup_valheimAcceptedSources
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
            id: virtualNetwork.id
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

