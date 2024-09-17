<#

AHS XenDesktop IGEL Daily Reboot
Owned by Infrastructure.Citrix@atlantichealth.org
Author: kyle.hedden@atlantichealth.org

Versions:
05/05/2023 - KH - Initial working version
05/31/2023 - KH - Updated controller list for IGEL infrastructure
02-02-2024 - KH - Adjusted Delivery Group filter to also gather new IGEX machines
#>

param(
    [CmdletBinding()]
    [Parameter(Position=0,Mandatory=$true)]
    [string]$DeliveryGroup
)

Enter-PSSession -ComputerName $ENV:COMPUTERNAME

#Define variables and load snap ins
asnp *citrix*
$site = "Cloud"
#Log path and Scheduled Task name variables
$LogPath = "C:\Powershell\XenDesktop_IGEL_Cloud_Daily_Reboots\Logs\" + (Get-Date -Format MM-dd-yy_) + $site + "_" + $DeliveryGroup + "_IGEL_Daily_Reboot.log"
#Delay in seconds between desktop reboot commands
$Delay = 5

#Nested function to create timestamps
function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

#Function to dump logs to defined $LogPath and update ui
Function Write-Log {
    [cmdletbinding()]
        Param (
            [string]$String
            )
    Out-File -InputObject ((Get-TimeStamp) + "," + "$String") -FilePath $LogPath -Append
    Write-Host ((Get-TimeStamp) + "," + "$String")

    If ($OutputBox) {
        $OutputBox.AppendText("`r`n " + (Get-TimeStamp) + " " + $String)
        $OutputBox.Refresh()
        $OutputBox.ScrollToCaret()
    }
}

#Function to launch reboots. prevents script but being run accidentally.
Function Reboot-IGEL {
    [Parameter(Position=0,Mandatory=$true)]
    [string]$DeliveryGroup
    
    Write-Log "Running on $ENV:COMPUTERNAME"

    Write-Log "Connecting to Citrix cloud..."
    try {
        Set-XDCredentials -CustomerId "wa5fqb8d30ef" -SecureClientFile "c:\Powershell\secureclient.csv" -ProfileType CloudApi -StoreAs Default
        $prof = Get-XDCredentials -ListProfiles
        Write-Log $prof[0].profiletype
        }
    catch {
        Write-Log "Connecting to Citrix cloud failed.  Check API credential file"
        }

    Write-Log "Starting reboots of unused desktops for environment $site $DeliveryGroup"

    #Gather Machines
    Try{
        Write-Log "Getting Desktops in group $DeliveryGroup from $site ..."
        $Desktops = Get-BrokerDesktop -DesktopGroupName $DeliveryGroup -MaxRecordCount 10000 | Where-Object {$_.SessionUserName -notlike "ahs\*"}
        $Total = $Desktops.Count
        $PoweredOn = $Desktops | Where {$_.PowerState -eq "On"}
        Write-Log "Finishing getting $Total Desktops from $site"
    }
    Catch {
        Write-Log "FAILED getting Desktops from $site"
    }

    Write-Log "Beginning execution of $DeliveryGroup Tasks.  Check for MFA prompt if not progressing"

    #Execute PS scheduled task
    If ($Desktops) {
        $Count = 0
        Write-Log "Starting $site - $DeliveryGroup - $Total machines - Check for MFA prompt if not progressing"
        ForEach ($Desktop in $PoweredOn) {
            $Name = $Desktop.HostedMachineName
            [int]$PercentComplete = ($Count/$($PoweredOn)* 100)
            Try {
                If ($Desktop.SessionUserName -notlike "ahs\*") {
                    New-BrokerHostingPowerAction -MachineName $Name -Action Restart
                    Write-Log "Rebooting $Name"
                }
            }
            Catch {
                Write-Log "FAILED to restart $Name"
                Write-Host "FAILED to start job on $Name" -ForegroundColor Red
            }
        $Count++
        Start-Sleep -Seconds $Delay
        }
        Write-Log "Completed $site - $DeliveryGroup"
    }
    ElseIf (!$Desktops) {
        Write-Log "No machines found in $site - $DeliveryGroup"
    }
}

Reboot-IGEL $DeliveryGroup