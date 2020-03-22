variable "location" {}

variable "tags" {
    type = map
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

variable "apimSku" {
    type = string
}

variable "apimSkuCapacity" {
    type = number
}

variable "apimPublisherName" {
    type = string
}

variable "apimPublisherEmail" {
    type = string
}

variable "apimProxyHostConfig" {
    type = map
}

variable "product" {
    type = map
}
