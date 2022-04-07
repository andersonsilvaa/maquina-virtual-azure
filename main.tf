terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

resource "azurerm_resource_group" "rg-infra-cloud" {
  name     = "infra-cloud-terraform"
  location = "westus2"
}

resource "azurerm_virtual_network" "vnet-infra-cloud" {
  name                = "vnet-infra"
  location            = azurerm_resource_group.rg-infra-cloud.location
  resource_group_name = azurerm_resource_group.rg-infra-cloud.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "Production"
    faculdade   = "Impacta"
    turma       = "ES23"
  }
}

resource "azurerm_subnet" "sub-infra-cloud" {
  name                 = "sub-infra"
  resource_group_name  = azurerm_resource_group.rg-infra-cloud.name
  virtual_network_name = azurerm_virtual_network.vnet-infra-cloud.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "ip-infra-cloud" {
  name                = "ip-infra"
  resource_group_name = azurerm_resource_group.rg-infra-cloud.name
  location            = azurerm_resource_group.rg-infra-cloud.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}

resource "azurerm_network_security_group" "nsg-infra-cloud" {
  name                = "nsg-infra"
  location            = azurerm_resource_group.rg-infra-cloud.location
  resource_group_name = azurerm_resource_group.rg-infra-cloud.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "web"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Production"
  }
}

resource "azurerm_network_interface" "nic-infra-cloud" {
  name                = "nic-infra"
  location            = azurerm_resource_group.rg-infra-cloud.location
  resource_group_name = azurerm_resource_group.rg-infra-cloud.name

  ip_configuration {
    name                          = "ip-infra-nic"
    subnet_id                     = azurerm_subnet.sub-infra-cloud.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-infra-cloud.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic-nsg-infra-cloud" {
  network_interface_id      = azurerm_network_interface.nic-infra-cloud.id
  network_security_group_id = azurerm_network_security_group.nsg-infra-cloud.id
}

resource "azurerm_storage_account" "sa-infra-cloud" {
  name                     = "sainfracloud"
  resource_group_name      = azurerm_resource_group.rg-infra-cloud.name
  location                 = azurerm_resource_group.rg-infra-cloud.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_linux_virtual_machine" "vm-infra-cloud" {
  name                  = "vm-infra"
  location              = azurerm_resource_group.rg-infra-cloud.location
  resource_group_name   = azurerm_resource_group.rg-infra-cloud.name
  network_interface_ids = [azurerm_network_interface.nic-infra-cloud.id]
  size                  = "Standard_D4_v5"

  admin_username                  = var.user
  admin_password                  = var.password
  disable_password_authentication = false

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  os_disk {
    name                 = "myosdisk1"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.sa-infra-cloud.primary_blob_endpoint
  }
}

data "azurerm_public_ip" "ip-infra-cloud" {
  name                = azurerm_public_ip.ip-infra-cloud.name
  resource_group_name = azurerm_resource_group.rg-infra-cloud.name
}

variable "user" {
  description = "Usuário da máquina"
  type        = string
}

variable "password" {}

resource "null_resource" "install-apache" {
  connection {
    type     = "ssh"
    host     = data.azurerm_public_ip.ip-infra-cloud.ip_address
    user     = var.user
    password = var.password
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y apache2",
    ]
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm-infra-cloud
  ]
}

resource "null_resource" "upload-app" {
  connection {
    type     = "ssh"
    host     = data.azurerm_public_ip.ip-infra-cloud.ip_address
    user     = var.user
    password = var.password
  }

  provisioner "file" {
    source      = "app"
    destination = "/home/adminuser"
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm-infra-cloud
  ]
}
