# Define parameters for the script
param (
    [Parameter(Mandatory = $true, HelpMessage = "Enter the name of the Azure resource group.")]
    [string]$ResourceGroupName
)

# Ensure the caller is authenticated to Azure
Write-Host "Logging in to Azure..." -ForegroundColor Yellow
try {
    Connect-AzAccount -ErrorAction Stop
}
catch {
    Write-Error "Failed to authenticate to Azure. Please ensure you have the correct permissions.";
    exit 1
}

# Let the caller select the subscription to use
Write-Host "Please select the appropriate Azure subscription:" -ForegroundColor Yellow
$subscription = Get-AzSubscription | Out-GridView -PassThru
if (-not $subscription) {
    Write-Error "No subscription selected. Exiting script.";
    exit 1
}

# Set the selected subscription context
Set-AzContext -SubscriptionId $subscription.Id

# Retrieve scaling details for all Azure Container Apps in the provided resource group
try {
    Write-Host "Retrieving container apps in resource group '$ResourceGroupName'..." -ForegroundColor Yellow
    $containerApps = az containerapp list --resource-group $ResourceGroupName -o json | ConvertFrom-Json

    if (-not $containerApps) {
        Write-Host "No container apps found in resource group '$ResourceGroupName'." -ForegroundColor Red
        exit 0
    }

    # Initialize an array to store container app scaling details
    $scalingDetails = @()

    # Loop through each container app to extract scaling details
    foreach ($app in $containerApps) {
        $scalingInfo = [PSCustomObject]@{
            AppName            = $app.name
            ResourceGroup      = $ResourceGroupName
            EnvironmentName    = $app.managedEnvironmentName
            Cpu                = $app.template.containers[0].resources.cpu
            Memory             = $app.template.containers[0].resources.memory
            MinReplicas        = $app.template.scale.minReplicas
            MaxReplicas        = $app.template.scale.maxReplicas
            ScalingRules       = @()
        }

        # Retrieve and add scaling rules
        if ($app.template.scale.rules) {
            foreach ($rule in $app.template.scale.rules) {
                $ruleDetails = [PSCustomObject]@{
                    RuleName     = $rule.name
                    RuleType     = $rule.custom.type
                    Metadata     = $rule.custom.metadata
                    Auth         = $rule.custom.auth
                }
                $scalingInfo.ScalingRules += $ruleDetails
            }
        }

        # Add the scaling info to the collection
        $scalingDetails += $scalingInfo
    }

    # Display the scaling details in table format
    Write-Host "
Scaling Details for Container Apps in Resource Group '$ResourceGroupName':" -ForegroundColor Cyan
    $scalingDetails | Format-Table -AutoSize

    # Output the scaling details as an object for further processing by the caller
    return $scalingDetails
}
catch {
    Write-Error "An error occurred while retrieving scaling details: $_"
    exit 1
}
