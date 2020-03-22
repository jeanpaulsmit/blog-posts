location = "westeurope"
prefix = "didago"
environment = "dev"
region = "we"
resourceFunction = "apim"

tags = {
  belongsto = "Core Resources",
  environment = "Production",
  costcenter = "Backend",
  owner = "IT"
}

apimSku = "Standard"
apimSkuCapacity = 1
apimPublisherName = "Didago IT Consultancy"
apimPublisherEmail = "apim@didago.nl"

apimProxyHostConfig = {
    hostName = "*.didago.nl"
    certificateName ="cert.pfx"
    certificateIssuer ="Self"
    certificatePasword ="Test123"
}

product = {
    productId = "some-product"
    productName = "Some Product"
    subscriptionRequired = true
    subscriptionsLimit = 10
    subscriptionKey = "some-custom-key-guid"
    adminSubscriptionKey = "admin-some-custom-key-guid"
    approvalRequired = true
    published = true
}
