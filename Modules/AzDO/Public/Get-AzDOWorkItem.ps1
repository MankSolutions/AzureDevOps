<#
.SYNOPSIS
	Gets an Azure DevOps work item

.DESCRIPTION
	Gets an Azure DevOps work item based on the information passed. There is
	a variety of ways to get a work item, such as Azure DevOps Id,
	tag, etc. It will use the token, org and project that is configured in the
	Set-Account function.

.PARAMETER ID
    The Id of the Azure DevOps Work Item that needs to be returned

.PARAMETER Tag
    The tag to look for within an Azure DevOps Work Item

.PARAMETER Query
    The query to run within Azure DevOps to find work items

.PARAMETER Url
    The Url of a work Item to find in Azure DevOps

.PARAMETER Ids
    Comma-delimited list of Ids to look up (max 200)
#>

Function Get-AzDOWorkItem {
    Param (
		[Parameter(Mandatory = $True)]
        [object]$Account,

        [Parameter(Mandatory = $True, ParameterSetName = 'AzDOId')]
        [string]$Id,

        [Parameter(Mandatory = $True, ParameterSetName = 'AzDOTag')]
        [string]$Tag,

        [Parameter(Mandatory = $True, ParameterSetName = 'AzDOQuery')]
        [string]$Query,

        [Parameter(Mandatory = $True, ParameterSetName = 'AzDOUrl')]
        [string]$Url,

        [Parameter(Mandatory = $True, ParameterSetName = 'AzDOList')]
        [string]$Ids
    )

    # Get the Azure DevOps work item based on Azure DevOps Id
    If ($Id) {
        $Uri = $($Account.AzDOUri) + '_apis/wit/workitems/' + $Id + '?api-version=5.1&$expand=all'
        $WorkItem = Invoke-RestMethod -Uri $Uri -headers $($Account.BasicAuthHeader) -Method Get
        Write-Output $WorkItem
    }

	# Get the Azure DevOps work item based on Azure DevOps Tag
    If ($Tag) {
        $Uri = $($Account.AzDOUri) + '_apis/wit/wiql?api-version=5.1&$expand=all'
        $WiqlQuery = "Select [System.Id], [System.Title], [System.State] From WorkItems Where [System.Tags] Contains Words '" + $Tag + "'"
        $Body = @{ query = $WiqlQuery }
        $BodyJson = @($Body) | ConvertTo-Json

		# Call REST method
        $WorkItem = Invoke-RestMethod -Uri $Uri -Method Post -ContentType "application/json" -Headers $($Account.BasicAuthHeader) -Body $BodyJson

		# Return array of work items
        Write-Output $WorkItem.workItems
    }

    # Get the Azure DevOps work item based on a Wiql query
    If ($Query) {
        $Uri = $($Account.AzDOUri) + '_apis/wit/wiql?timePrecision=true&api-version=5.1&$expand=all'
        $Body = @{ query = $Query }
        $BodyJson = @($Body) | ConvertTo-Json

		# Call REST method
        $WorkItem = Invoke-RestMethod -Uri $Uri -Method Post -ContentType "application/json" -Headers $($Account.BasicAuthHeader) -Body $BodyJson

		# Return array of work items
        Write-Output $WorkItem
    }

    # Get the Azure DevOps work item based on Azure DevOps Url (REST API return)
    If ($Url) {
        $Uri = $Url + '?api-version=5.1&$expand=all'
        $WorkItem = Invoke-RestMethod -Uri $Uri -headers $($Account.BasicAuthHeader) -Method Get
        Write-Output $WorkItem
    }

     # Get a list of Azure DevOps work items
     If ($Ids) {
        $Uri = $($Account.AzDOUri) + '_apis/wit/workitems?ids=' + $Ids + '&$expand=all&api-version=5.1'
        $WorkItem = Invoke-RestMethod -Uri $Uri -headers $($Account.BasicAuthHeader) -Method Get
        Write-Output $WorkItem
    }
}