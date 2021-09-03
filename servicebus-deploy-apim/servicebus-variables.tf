variable "location" {}

variable "region" {
    type = string
    default = "we"
}

variable "prefix" {
    type = string
    default = "didago"
}

variable "environment" {
    type = string
}

variable "tags" {
    type = map
}
