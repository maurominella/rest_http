$tenant_id = "1e7a05d2-22ba-4578-a894-9b7eed47dfe1" # name: aclouddigitaloutlook.onmicrosoft.com

$subscription_id = "697b44b7-c15e-42a7-ad47-0aa74c7dfa18" # name: RAI DIGITAL

$sourceResourceId = "/subscriptions/$subscription_id/resourceGroups/analyticspoc-resourcegroup-we/providers/Microsoft.Storage/storageAccounts/analyticsdatalakewe"

# Azure CLI (az) and the Az PowerShell module maintain separate authentication contexts. 
# This means that even if you authenticate successfully in PowerShell (Connect-AzAccount and Set-AzContext), 
# the Azure CLI might not have the same authentication context or token. We need to re-authenticating specifically on bopth systems.

# Az PowerShell module uses cmdlets that follow the PowerShell naming convention: verb-noun format. These commands are specifically designed for working in PowerShell environments
Connect-AzAccount -Tenant $tenant_id
Get-AzSubscription -TenantId $tenant_id
Set-AzContext -SubscriptionId $subscription_id

# Azure CLI commands start with the az prefix. These are cross-platform commands used to interact with Azure services via the CLI (Command Line Interface) and rely on Python.
az login --tenant $tenant_id
az account set --subscription $subscription_id
$listeners_all_json = az eventgrid event-subscription list --source-resource-id $sourceResourceId

$listeners_all_obj = $listeners_all_json | ConvertFrom-Json # takes a JSON-formatted string and converts it into a PowerShell object. This object makes it easier to work with JSON data

$listeners_all_count = $listeners_all_obj.Count

$listeners_names_all = $listeners_all_obj | ForEach-Object { $_.name }

$listeners_names_all.GetType() # it's a System.Array of strings, e.g. Object[]

$listeners_names_all | Set-Content -Path "listeners_names_all.txt" # check in %USERPROFILE% path, or manually use a specific path

$listeners_names_tokeep = Get-Content -Path "listeners_names_tokeep.txt"
$listeners_names_tokeep.Count

$string_to_look_for = "databricks-query-bf5171cf-b223-43bd-abf6-19e0c1e68946-source-0" 

$foundString = $listeners_names | Where-Object { $_ -like "*$string_to_look_for*" }
if ($foundString) {
    Write-Output "Found: $foundString"
} else {
    Write-Output "The string 'example-string' is not in the list."
}


function Remove-UnwantedEventGridListeners {
    param (
        [string]$sourceResourceId,
        [array]$listeners_names_tokeep
    )

    # Fetch all active listeners
    $listeners_all_obj = az eventgrid event-subscription list --source-resource-id $sourceResourceId | ConvertFrom-Json

    foreach ($listener in $listeners_all_obj) {
        $listenerName = $listener.name

        # Skip deletion if the listener is in the keep list
        if ($listeners_names_tokeep -contains $listenerName) {
            Write-Host "Skipping listener: $listenerName"
            continue
        }

        # Delete unwanted listener
        Write-Host "Deleting listener: $listenerName"
        az eventgrid event-subscription delete --source-resource-id $sourceResourceId --name $listenerName
    }

    Write-Host "Cleanup complete!"
}

# Example usage


# Call the function
Remove-UnwantedEventGridListeners -sourceResourceId $sourceResourceId -listeners_names_tokeep $listeners_names_tokeep