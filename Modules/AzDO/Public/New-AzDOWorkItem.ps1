<#
.SYNOPSIS
	Creates a new work item in Azure DevOps

.DESCRIPTION
	This function creates an Azure DevOps work item based on the passed parameters.
	It will use the token, org and project that is configured in the Set-Account function.

.PARAMETER Account
    The account object used to authenticate the REST API request

.PARAMETER WorkItemType
    The type of work item to create (e.g. PBI, Bug, Task)

.PARAMETER WorkItemFields
    A hashtable of fields to set on the work item
#>

Function New-AzDOWorkItem {
    Param (
		[Parameter(Mandatory = $True)]
        [object]$Account,

        [Parameter(Mandatory = $True)]
        [string]$WorkItemType,

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

    # We convert the Json body to byte since it handles the formatting better
    $ByteBody = ([System.Text.Encoding]::UTF8.GetBytes($Body))


    # Call Azure DevOps API to create work item
    $Uri = $($Account.AzDOUri) + "_apis/wit/workitems/$" + $WorkItemType + "?api-version=5.1-preview.3"
    $WorkItem = Invoke-RestMethod `
        -Uri $Uri `
        -Method Post `
        -ContentType "application/json-patch+json" `
        -Headers $($Account.BasicAuthHeader) `
        -Body $ByteBody

	Write-Output $WorkItem
}