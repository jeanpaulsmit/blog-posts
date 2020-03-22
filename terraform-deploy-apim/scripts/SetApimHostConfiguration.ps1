#--------------------------------------------------------------
# Script to setup custom proxy host configuration on APIM
#--------------------------------------------------------------
param
(
    [string] $resourceGroupName,
    [string] $apimServiceName,
    [string] $apiProxyHostname,
    [string] $kvCertificateSecret
)

# Allow cmdlets to be used
Install-Module -Name Az -AllowClobber -Scope CurrentUser -force

$subscriptionId = $env:ARM_SUBSCRIPTION_ID
$tenantId = $env:ARM_TENANT_ID
$clientId = $env:ARM_CLIENT_ID
$secret = $env:ARM_CLIENT_SECRET

$securesecret = ConvertTo-SecureString -String $secret -AsPlainText -Force
$Credential = New-Object pscredential($clientId,$securesecret)
Connect-AzAccount -Credential $Credential -Tenant $tenantId -ServicePrincipal
Select-AzSubscription $subscriptionId

# Create the HostnameConfiguration object for Proxy endpoint
$proxyConfiguration = New-AzApiManagementCustomHostnameConfiguration -Hostname $apiProxyHostname -HostnameType Proxy -KeyVaultId $kvCertificateSecret

# Get reference to APIM instance and apply the configuration to API Management
$apimContext = Get-AzApiManagement -ResourceGroupName $resourceGroupName -Name $apimServiceName
$apimContext.ProxyCustomHostnameConfiguration = $proxyConfiguration 
Set-AzApiManagement -InputObject $apimContext
