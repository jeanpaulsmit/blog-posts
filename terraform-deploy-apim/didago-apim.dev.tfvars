location = "westeurope"
prefix = "didago"
environment = "dev"
region = "we"
resourceFunction = "apim"

tags = {
  belongsto = "Core Resources",
  environment = "Development",
  costcenter = "Backend",
  owner = "IT"
}

apimSku = "Developer"
apimSkuCapacity = 1
apimPublisherName = "Didago IT Consultancy"
apimPublisherEmail = "apim-dev@company.com"

apimProxyHostConfig = {
    hostName = "*.company.com"
    certificateName ="cert.pfx"
    certificateIssuer ="Self"
    certificatePasword ="Test123"
}

product = {
    productId = "some-product"
    productName = "Some Product"
    subscriptionRequired = true
    subscriptionsLimit = 10
    subscriptionKey = "some-custom-key-guid-dev"
    adminSubscriptionKey = "admin-some-custom-key-guid-dev"
    approvalRequired = true
    published = true
}
