<#
.SYNOPSIS
	Deletes a work item with a given Id

.DESCRIPTION
	This function deletes an Azure DevOps work item based on its Id

.PARAMETER Id
    The Id of the work item that needs to be deleted

.EXAMPLE
    Remove-AzDOWorkItem -ID 123456
#>

Function Remove-AzDOWorkItem {
    Param (
		[Parameter(Mandatory = $True)]
        [object]$Account,

        [Parameter(Mandatory = $True)]
        [string]$Id
    )

    $Uri = $($Account.AzDOUri) + '_apis/wit/workitems/' + $Id + '?api-version=5.0'
    $WorkItem = Invoke-RestMethod -Uri $Uri -headers $($Account.BasicAuthHeader) -Method Delete
	Write-Output $WorkItem
}