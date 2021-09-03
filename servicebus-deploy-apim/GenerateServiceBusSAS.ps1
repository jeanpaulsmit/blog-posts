
# Read input in JSON format
$jsonpayload = [Console]::In.ReadLine()
$json = ConvertFrom-Json $jsonpayload

# Execute generation of SAS token
[Reflection.Assembly]::LoadWithPartialName("System.Web")| out-null
$Expires=([DateTimeOffset]::Now.ToUnixTimeSeconds())+$json.sasExpiresInSeconds
$SignatureString=[System.Web.HttpUtility]::UrlEncode($json.servicebusUri)+ "`n" + [string]$Expires
$HMAC = New-Object System.Security.Cryptography.HMACSHA256
$HMAC.key = [Text.Encoding]::ASCII.GetBytes($json.policyKey)
$Signature = $HMAC.ComputeHash([Text.Encoding]::ASCII.GetBytes($SignatureString))
$Signature = [Convert]::ToBase64String($Signature)
$SASToken = "SharedAccessSignature sr=" + [System.Web.HttpUtility]::UrlEncode($json.servicebusUri) + "&sig=" + [System.Web.HttpUtility]::UrlEncode($Signature) + "&se=" + $Expires + "&skn=" + $json.policyName

# Return to caller in JSON format
$outputJson = @{
  sas = "$SASToken";
} | ConvertTo-Json

Write-Output $outputJson
