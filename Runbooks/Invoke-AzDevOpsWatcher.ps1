<#
.SYNOPSIS
	Azure DevOps watcher runbook

.DESCRIPTION
    This runbook is a generic Azure DevOps watcher script. It contains multiple
	queries where it is looking for certain conditions and then calls an action
	runbook to perform a particular action. The following are the items it is
	currently watching for:

	1. HERE
	
	2. HERE
#>

# Verbose messages are written to the log in AA testing pane
$VerbosePreference = "Continue"

Try {
	Function Main {
		# Get date ranges
		$StartDate = Get-AutomationVariable -Name 'AzDevOpsWatcher_LastCheckedDate' -Verbose:$False
		$EndDate = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
		Write-LogMessage -Message "Start Date: $StartDate"
		Write-LogMessage -Message "End Date:   $EndDate"

		# ********** 2. Check for completed TAR approvals **********
		# Get ADO work items
		$AdoQuery = "SELECT [System.Id] `
			FROM WorkItems `
			WHERE [System.Tags] CONTAINS `"TA Request`"
			AND [System.ChangedDate] > '$StartDate'
			AND (
				[Custom._COMPANY_TarApprovalState] = 'Approve'
				OR [Custom._COMPANY_TarApprovalState] = 'Reject'
			)
			AND [System.State] = 'Pending Approval'
			AND [System.TeamProject] = 'PROJECT NAME'"

		$Command = @{
			ScriptBlock = {Param ($param1,$param2) Get-AzDOWorkItem -Account $param1 -Query $param2 -Verbose:$False}
			ArgumentList = $AzDOAccount, $AdoQuery
		}
		$TarItems = Invoke-COMPANYCommand -CommandParameters $Command
		Write-LogMessage -Message "$($TarItems.workItems.Count) completed TAR approvals"

		# Loop through each to update TAR requests
		ForEach ($Item In $TarItems.workItems) {
			# Build the properties object
			$Properties = @{
				Action = "PostTarApproval"
				Id = $Item.id
			}

			# Invoke action runbook
			$r = Start-AzAutomationRunbook `
				-Name "Invoke-AzDevOpsAction" `
				-AutomationAccountName $AAEnvironment `
				-ResourceGroupName "COMPANY-AA" `
				-Parameters $Properties `
				-RunOn $AAEnvironment
			Write-LogMessage -Message "Invoked Action runbook: Post TAR approval for ADO $($Item.id)"
		}

		# Set new last checked date
		$StartDate = Set-AutomationVariable -Name "AzDevOpsWatcher_LastCheckedDate" -Value "$EndDate" -Verbose:$False
		Write-LogMessage -Message "New start date set: $EndDate"
	}

	Function Write-LogMessage {
        Param (
            [Parameter(Mandatory=$True)]
            [string]$Message
        )

		Write-Verbose $Message
    }

	# Main
	Main
}

Catch {
	# Write to error stream and throw terminating error
	$LineNo = $Error[0].InvocationInfo.ScriptLineNumber.ToString()
	$Line = $Error[0].InvocationInfo.Line.ToString()
	$Err = $Error[0]
	$Err = "Error: ${Err}, LineNo: ${LineNo}, Line Text: ${Line}"
    Write-Error $Err
    Throw $Err
}

Finally {
	$SyncFinish = Get-Date
	$SyncSeconds = [Math]::Round(($SyncFinish - $script:SyncStart).TotalSeconds, 2)
	Write-LogMessage -Message "Invoke-AzDevOpsWatcher ran in $SyncSeconds seconds"
	Write-LogMessage -Message "*** Invoke-AzDevOpsWatcher Finished ***"
}