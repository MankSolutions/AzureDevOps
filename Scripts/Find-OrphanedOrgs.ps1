<#
.SYNOPSIS
	Finds Azure DevOps orgs that are orphaned

.DESCRIPTION
    Azure DevOps allows users in the AAD tenant to create their own ADO orgs.
    When a user leaves the company, these orgs are still tied to the AAD tenant
    and are orphaned since the owner account is disabled. This script reads from
    a CSV file of current orgs tied to the tenant and finds where the owner is
    disabled in AD. These orgs can then be taken over and deleted.

    This script is meant to be run as part of the normal quarterly ADO maintenance
#>

$VerbosePreference = "Continue"

Try {
    # Import ActiveDirectory Module
    Import-Module ActiveDirectory -Verbose:$False

    # Get the CSV of ADO orgs
    $File = Import-Csv -Path "C:\PATHERE\Azure_DevOps_Organizations_In_GUIDHERE.csv"

    # Loop through each org
    $n = 0
    ForEach ($Org In $File) {
        # Get the AD User
        $User = Get-ADUser -Filter "EmailAddress -eq '$($Org.Owner)'" `
            -Properties * | Select-Object Name, Enabled

        # Check if user is disabled
        If ($User.Enabled -eq $False) {
            $n += 1
            Write-Host $User.Name - $User.Enabled - $Org.Url -ForegroundColor Red
        }
    }

    # Check if there were any disabled orgs
    If ($n -eq 0) {
        Write-Host "Didn't find any disabled org owners" -ForegroundColor Green
    }
}

Catch {
	# Write to error stream and throw terminating error
    Write-Error $Error[0]
}