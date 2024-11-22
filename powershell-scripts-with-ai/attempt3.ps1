<#
.SYNOPSIS
    Retrieves scaling details (CPU, Memory, replicas, and scaling rules) for all Azure Container Apps within a specified resource group.

.DESCRIPTION
    This script retrieves scaling details for all Azure Container Apps in a specified resource group. It requires the caller to authenticate to Azure and select the appropriate subscription before executing the main logic.

.PARAMETER ResourceGroupName
    The name of the Azure resource group containing the container apps.

.EXAMPLE
    .\Get-ContainerAppScalingDetails.ps1 -ResourceGroupName "MyResourceGroup"
    This command retrieves scaling details for all container apps in the specified resource group "MyResourceGroup".

.NOTES
    Author: [Your Name]
    Date: [Date]
    Version: 1.0
    Dependencies: Azure CLI
    Make sure you have the necessary permissions to access the specified resource group and container apps.
#>

# Define parameters for the script
param (
    [Parameter(Mandatory = $true, HelpMessage = "Enter the name of the Azure resource group.")]
    [string]$ResourceGroupName
)

# Step 1: Ensure the caller is authenticated to Azure using Azure CLI
Write-Host "Logging in to Azure..." -ForegroundColor Yellow
try {
    az login --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to authenticate to Azure. Please ensure you have the correct permissions."
    }
}
catch {
    Write-Error $_
    exit 1
}

# Step 2: Let the caller select the subscription to use
Write-Host "Please select the appropriate Azure subscription:" -ForegroundColor Yellow
$subscriptions = az account list -o json | ConvertFrom-Json
$subscription = $subscriptions | Out-GridView -PassThru
if (-not $subscription) {
    Write-Error "No subscription selected. Exiting script."
    exit 1
}

# Step 3: Set the selected subscription context
az account set --subscription $subscription.id
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set subscription context. Exiting script."
    exit 1
}

# Step 4: Retrieve scaling details for all Azure Container Apps in the provided resource group
try {
    Write-Host "Retrieving container apps in resource group '$ResourceGroupName'..." -ForegroundColor Yellow
    $containerApps = az containerapp list --resource-group $ResourceGroupName -o json | ConvertFrom-Json

    if (-not $containerApps) {
        Write-Host "No container apps found in resource group '$ResourceGroupName'." -ForegroundColor Red
        exit 0
    }

    # Initialize an array to store container app scaling details
    $scalingDetails = @()

    # Step 5: Loop through each container app to extract scaling details
    foreach ($app in $containerApps) {
        # Extract CPU and Memory details from the first container (assuming single-container apps)
        $cpu = $null
        $memory = $null
        if ($app.properties.template.containers -and $app.properties.template.containers.Count -gt 0) {
            $cpu = $app.properties.template.containers[0].resources.cpu
            $memory = $app.properties.template.containers[0].resources.memory
        }

        # Create an object to store scaling details for each container app
        $scalingInfo = [PSCustomObject]@{
            AppName            = $app.name
            ResourceGroup      = $ResourceGroupName
            EnvironmentName    = $app.managedEnvironmentId
            Cpu                = $cpu
            Memory             = $memory
            MinReplicas        = $app.properties.template.scale.minReplicas
            MaxReplicas        = $app.properties.template.scale.maxReplicas
            ScalingRules       = @()
        }

        # Step 6: Retrieve and add scaling rules, if any
        if ($app.properties.template.scale.rules) {
            foreach ($rule in $app.properties.template.scale.rules) {
                $ruleDetails = [PSCustomObject]@{
                    RuleName     = $rule.name
                    RuleType     = $rule.type
                    Metadata     = $rule.metadata
                    Auth         = $rule.auth
                }
                $scalingInfo.ScalingRules += $ruleDetails
            }
        }

        # Add the scaling info to the collection
        $scalingDetails += $scalingInfo
    }

    # Step 7: Display the scaling details in table format
    Write-Host "
Scaling Details for Container Apps in Resource Group '$ResourceGroupName':" -ForegroundColor Cyan
    $scalingDetails | Format-Table -AutoSize

    # Step 8: Output the scaling details as an object for further processing by the caller
    return $scalingDetails
}
catch {
    Write-Error "An error occurred while retrieving scaling details: $_"
    exit 1
}

# Notes:
# - This script requires the Azure CLI to be installed and available in the system PATH.
# - Use this script responsibly in a production environment by incorporating proper access controls and monitoring.
