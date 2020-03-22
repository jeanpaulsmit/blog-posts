variable "tags" {
    type = map
}

variable "location" {
    type = string
    default = "westeurope"
}

variable "region" {
    type = string
    default = "we"
}

variable "prefix" {
    type = string
    default = "didago"
}

variable "resourceFunction" {
    type = string
    default = "apim"
}

variable "environment" {
    type = string
}

variable "storageAccountSku" {
    default = {
        tier = "Standard"
        type = "GRS"
    }
}
