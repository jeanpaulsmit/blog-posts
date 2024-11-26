<#
.SYNOPSIS
    This script outputs the scaling details like CPU, memory, number of replicas, and custom scaling rules for all Azure Container Apps in a specified resource group.

.DESCRIPTION
    The caller of this script will provide the name of the resource group. The script ensures the caller logs in to Azure to select the correct subscription.

.PARAMETER ResourceGroupName
    The name of the resource group containing the Azure Container Apps.

.EXAMPLE
    .\Get-AzureContainerAppScalingDetails.ps1 -ResourceGroupName "MyResourceGroup"

.NOTES
    Author: Your Name
    Date: 2024-11-26
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName
)

# Ensure the caller is logged in to Azure
if (-not (Get-AzContext)) {
    Write-Host "Please log in to Azure..."
    Connect-AzAccount
}

# Function to get scaling details for a single Azure Container App
function Get-ContainerAppScalingDetails {
    param (
        [string]$ContainerAppName
    )

    try {
        $containerApp = Get-AzContainerApp -ResourceGroupName $ResourceGroupName -Name $ContainerAppName

        # Extract scaling rules
        $scalingRules = $containerApp.ScaleRule | ForEach-Object {
            [PSCustomObject]@{
                Name     = $_.Name
                Type     = $_.CustomType
            }
        }

        $scalingDetails = @{
            ContainerAppName    = $ContainerAppName
            CPU                 = $containerApp.TemplateContainer[0].ResourceCpu
            Memory              = $containerApp.TemplateContainer[0].ResourceMemory
            MinReplicas         = $containerApp.ScaleMinReplica
            MaxReplicas         = $containerApp.ScaleMaxReplica
            CustomScalingRules  = $scalingRules
        }
        return $scalingDetails
    }
    catch {
        Write-Error "Failed to get scaling details for Container App: $ContainerAppName. Error: $_"
        return $null
    }
}

# Get all Azure Container Apps in the specified resource group
try {
    $containerApps = Get-AzContainerApp -ResourceGroupName $ResourceGroupName
}
catch {
    Write-Error "Failed to get Azure Container Apps in resource group: $ResourceGroupName. Error: $_"
    exit 1
}

# Initialize an array to hold the scaling details
$scalingDetailsArray = @()

# Iterate through each Container App and get the scaling details
foreach ($containerApp in $containerApps) {
    $scalingDetails = Get-ContainerAppScalingDetails -ContainerAppName $containerApp.Name
    if ($scalingDetails) {
        $scalingDetailsArray += $scalingDetails
    }
}

# Display an overview of the scaling details
$scalingDetailsArray | Format-Table -AutoSize

# Output the information as an object
$scalingDetailsArray
