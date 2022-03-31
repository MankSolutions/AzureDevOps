<#
.SYNOPSIS
	Finds and updates an Azure DevOps work item

.DESCRIPTION
	This function uses the Get-AzDOWorkItem function to find an already existing
	Azure DevOps work item and update it.

.PARAMETER Account
    The account object used to authenticate the REST API request

.PARAMETER WorkItemId
    The Id of the work item to update

.PARAMETER WorkItemFields
    A hashtable of fields to update on the work item
#>

Function Update-AZDOWorkItem {
    Param (
		[Parameter(Mandatory = $True)]
        [object]$Account,

        [Parameter(Mandatory = $True)]
        [string]$WorkItemId,

        [Parameter(Mandatory = $True)]
        [object]$WorkItemFields
    )

    # Delcare the Body variable
    $Body = [System.Collections.ArrayList]@()

    # Loop through the passed work item fields and add to array
    ForEach ($Field in $WorkItemFields.GetEnumerator()) {
        $r = $Body.Add(@{
            op    = "add"
            path  = $Field.Name
            value = $Field.Value
        })
    }

    # Can not use convertto-json pipeline command if there is only one
    # field due to the outer hashtable being stripped away. We get around
    # this by calling it this way
    $Body = ConvertTo-Json @($Body) -Depth 3 -Compress

    # Call Azure DevOps API to update work item
    $Uri = $($Account.AzDOUri) + "_apis/wit/workitems/" + $WorkItemId + "?api-version=5.0"
    $WorkItem = Invoke-RestMethod `
        -Uri $Uri `
        -Method Patch `
        -ContentType "application/json-patch+json" `
        -Headers $($Account.BasicAuthHeader) `
        -Body $Body

	# Return work item
	Write-Output $WorkItem
}