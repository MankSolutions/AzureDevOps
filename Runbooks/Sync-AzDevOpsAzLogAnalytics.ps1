<#
.SYNOPSIS
	Syncs ALA log alerts with Azure DevOps

.DESCRIPTION
	This runbook is called by a Power Automate flow. That flow is called by
    an Azure Monitor webhook. This script inputs error logs from ALA and
    creates bugs in ADO. If a bug already exists by process name and error
    code, it will only update that existing bug.

.PARAMETER AlertPayload
	The payload in JSON of the alert detail from Azure Monitor
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$True)]
	[object]$AlertPayload
)

# Verbose messages are written to the log in AA testing pane
$VerbosePreference = "Continue"

Try {
    Function Main {
		# Start
		Write-LogMessage -Message "*** Sync-AzDevOpsAzLogAnalytics Started ***"
		Write-LogMessage -Message "Hybrid Worker: $env:COMPUTERNAME"
		$script:SyncStart = Get-Date

		# Import modules
		$Modules = @("AzDO", "COMPANY")
		ForEach ($Module In $Modules) {
			Import-Module $Module -Verbose:$False
			Write-LogMessage -Message "PowerShell module $Module imported"
		}

		# Connect to Azure DevOps
		$PAT = Get-AutomationVariable -Name "USER_AzDevOpsPAT" -Verbose:$False
		If ($PAT) {
			$AzDOAccount = Set-AzDOAccount -Token $PAT -Organization "COMPANY" -Project $AlertPayload.AdoProjectName -Verbose:$False
			Write-LogMessage -Message "ADO Context Set: $($AzDOAccount.AzDOUri)"
		}
		Else {
			Throw "AzDO PAT not set in Automation variables"
		}
		$AdoAreaPath = $AlertPayload.AdoAreaPath
		Write-LogMessage -Message "ADO Area Path: $AdoAreaPath"

		# Get the time zone info and reformat dates
		$CurrentTimeZone = (Get-WmiObject Win32_TimeZone).StandardName
		$TimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($CurrentTimeZone)
		$AlertPayload.SearchIntervalStartTime = ([System.TimeZoneInfo]::ConvertTimeFromUtc($($AlertPayload.SearchIntervalStartTime), $TimeZone)).ToString()
		$AlertPayload.SearchIntervalEndTime = ([System.TimeZoneInfo]::ConvertTimeFromUtc($($AlertPayload.SearchIntervalEndTime), $TimeZone)).ToString()

		# Log alert payload properties (but not search results)
		ForEach ($Property In $AlertPayload.PSObject.Properties | Where-Object {$_.Name -ne "SearchResults"}) {
			Write-LogMessage -Message "$($Property.Name): $($Property.Value)"
		}

		# Build and populate data table with search results
		$Table = New-Object System.Data.Datatable
		ForEach ($Column In $AlertPayload.SearchResults.tables[0].columns) {
			[void]$Table.Columns.Add($Column.name)
			$Table.Columns["$($Column.name)"].DefaultValue = ""
		}
		ForEach ($Item In $AlertPayload.SearchResults.tables[0].rows) {
			$Row = $Table.Rows.Add($Item)
		}
		Write-LogMessage -Message "$($Table.Rows.Count) rows returned in the search"

		# Loop through each search result
		ForEach ($Row In $Table) {
			# Set some process-related variables
			$Process = $Row.$($AlertPayload.ProcessColumnName)
			$ErrorCode = -join $Row.$($AlertPayload.ErrorCodeColumnName)[0..100]
            $MessageCount = $Row.count_
			Write-LogMessage -Message "Process: $Process"
			Write-LogMessage -Message "ErrorCode: $ErrorCode"
            Write-LogMessage -Message "Count: $MessageCount"

			# Get ADO work items
			$AdoProjectName = $($AzDOAccount.AzDOProject).Replace("%20"," ")
			$ErrorCodeFormatted = $ErrorCode.Replace("'","''")
			$AdoQuery = "SELECT [System.Id]
				FROM WorkItems
				WHERE [System.TeamProject] = '$AdoProjectName'
				AND [System.WorkItemType] = 'Bug'
				AND [System.State] <> 'Done'
				AND [System.State] <> 'Removed'
				AND [Custom._COMPANY_AlaProcessName] = '$Process'
				AND [Custom._COMPANY_AlaErrorCode] = '$ErrorCodeFormatted'"

			$Command = @{
				ScriptBlock = {Param ($param1,$param2) Get-AzDOWorkItem -Account $param1 -Query $param2 -Verbose:$False}
				ArgumentList = $AzDOAccount, $AdoQuery
			}
			$AdoItems = Invoke-COMPANYCommand -CommandParameters $Command
			Write-LogMessage -Message "$($AdoItems.workItems.Count) open bug(s) found"

            # Check if existing bugs exist
            If ($AdoItems.workItems.Count -eq 0) {
                # NEW Bug
                # Set ADO fields
                $WiType = "Bug"

				# Get the ALA Url
				$AlaUrl = Get-AlaUrl -ProcessName $Process -ErrorCodeName $ErrorCode -Technology $AlertPayload.Technology

				# Build message description
				$DescriptionFields = @{
					"01Process" = "$Process (<a href=`"$AlaUrl`">Click to view in ALA</a>)"
					"02Error Code" = $ErrorCode
					"03Technology" = $AlertPayload.Technology
					"04Environment Type" = $AlertPayload.EnvironmentType
					"05Alert Rule Name" = $AlertPayload.AlertRuleName
					"06First Occurrence" = $AlertPayload.SearchIntervalStartTime
				}
				ForEach ($Field In ($DescriptionFields.GetEnumerator() | Sort-Object -Property Name)) {
					$Description = $Description + "<b>$($Field.Name.Substring(2)):</b> $($Field.Value)<br>"
				}

                # ADO fields
                $AdoFields = @{
                    "/fields/System.Title" = If ($ErrorCode) {"ALA Log Error: $Process - $ErrorCode"} Else {"ALA Log Error: $Process"}
                    "/fields/Microsoft.VSTS.TCM.ReproSteps" = $Description
                    "/fields/System.State" = "New"
                    "/fields/System.AreaPath" = $AdoAreaPath
                    "/fields/Custom._COMPANY_AlaProcessName" = $Process
                    "/fields/Custom._COMPANY_AlaErrorCode" = $ErrorCode
					"/fields/Custom._COMPANY_AlaMessageCount" = $MessageCount
					"/fields/Custom._COMPANY_AlaOccurrenceCount" = "1"
                }

                # Create the ADO work item
                $WI = New-AzDOWorkItem `
                    -Account $AzDOAccount `
                    -WorkItemType "$WiType" `
                    -WorkItemFields $AdoFields `
                    -Verbose:$False
                Write-LogMessage -Message "Azure DevOps $WiType $($WI.id) CREATED"
            }
			Else {
				# EXISTING Bug
				ForEach ($Item In $AdoItems.workItems) {
					# Get ADO item
					$WI = Get-AzDOWorkItem `
						-Account $AzDOAccount `
						-Id $Item.id `
						-Verbose:$False

					# ADO fields
					$AdoFields = @{
						"/fields/Custom._COMPANY_AlaMessageCount" = $($Wi.fields."Custom._COMPANY_AlaMessageCount") + $MessageCount
						"/fields/Custom._COMPANY_AlaOccurrenceCount" = $($Wi.fields."Custom._COMPANY_AlaOccurrenceCount") + 1
					}

					# Update the ADO work item
					$WI = Update-AzDOWorkItem `
						-Account $AzDOAccount `
						-WorkItemId $Item.id `
						-WorkItemFields $AdoFields `
						-Verbose:$False
					Write-LogMessage -Message "Updated ALA counts on ADO Bug $($WI.id)"
				}
			}

            # Null Description for next iteration
            $Description = $null
		}
	}

	Function Get-AlaUrl {
        Param (
            [Parameter(Mandatory=$True)]
            [string]$ProcessName,

            [Parameter(Mandatory=$False)]
            [string]$ErrorCodeName = "",

            [Parameter(Mandatory=$True)]
            [string]$Technology
        )

		# Set needed variables
        $SubscriptionId = Get-AutomationVariable -Name "Azure_SubscriptionId" -Verbose:$False
        $ResourceGroup = "COMPANY-OMS"
        $Workspace = "COMPANYoms"

		$ErrorCodeNameFormatted = $ErrorCodeName.Replace("'","\'")
        $QueryString = "${Technology}ProcessErrors ('$ProcessName', '$ErrorCodeNameFormatted')"

        # Get the ALA Url
        $AlaUrl = Get-AzLogAnalyticsQueryUrl `
            -SubscriptionId $SubscriptionId `
            -ResourceGroup $ResourceGroup `
            -Workspace $Workspace `
            -QueryString $QueryString

        # Output ALA Url
        Write-Output $AlaUrl
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
	Write-LogMessage -Message "Sync-AzDevOpsAzLogAnalytics ran in $SyncSeconds seconds"
	Write-LogMessage -Message "*** Sync-AzDevOpsAzLogAnalytics Finished ***"
}