#requires -version 3.0

<#
    This script can be used to intelligently power up/down machines on prem or in the cloud (AWS,Azure,GCP) based upon schedules or 'load'.
    Steve Noel
    7-10-2018

    Modification history:
    (Date and Change Description)
#>

<#
.SYNOPSIS
This script can be used to intelligently power up/down machines on prem or in the cloud (AWS,Azure,GCP) based upon schedules or 'load'.

.DESCRIPTION
.PARAMETER (parameter1)
(Enter details on how paraemter works/requirements)

.PARAMETER (parameter2)
(Enter details on how paraemter works/requirements)

Azure:
Install-Module -Name azurerm
Enable-AzureRmContextAutosave
Connect-AzureRmAccount (sign in)


.EXAMPLE
& '.\(Name of Script).ps1' -DeliveryController Citrix-ddc1 -LogDir C:\temp -ScheduleMode -SchedStart 6 -SchedFinish 16 -DGName DG-Server2012R2 -BaseTag Base -OnPrem -LogOnly
This script will look at the dlivery group 'DG-Server2012R2' on the Delivery Controller 'Citrix-ddc1'.  It's using the mode 'ScheduleMode' which powers up/down machines based upon Times set
in 'SchedStart' and 'SchedFinish' (military time).  At 'SchedStart', it makes sure machines are powered on and available for connections all the way up to the 'SchedFinish' time.  The 'BaseTag' Base is
used to denote that these machines won't get controlled in this script.  These are your base machines that you don't want power managed.  The 'OnPrem' paraemter is notifying the script to
use certain commands geared for on premesis deployments.  Lastly we are using the 'LogOnly' parameter to put the script in an audit mode. So it will report everything, but won't actually execute the action.

.EXAMPLE
& '.\(Name of Script).ps1' -DeliveryController Citrix-ddc1 -LogDir C:\temp -ScheduleMode -SchedStart 6 -SchedFinish 16 -DGName DG-Server2012R2 -BaseTag Base -IgnoreTag UnIntelli -AWS -AWSProfile My-AWS-Credentials -SMTPserver smtp.domain.local -ToAddress Steve@asdf.com -FromAddress Steve@asdf.com -Email
This script performs like above but is geared for AWS deployments, with the -AWS parameter.  It also ignores any VDAs tagged with 'UnIntelli' tag.  It uses the AWS Credential Profile 'AWSProfile' called My-AWS-Credentials.  Lastly it emails the results to the defined email addresses.

.NOTES
(Enter specific things to note for this script)

#>

[CmdletBinding()]

Param
(
    [Parameter(Mandatory=$True,Position=1)][string]$DeliveryController,
    [Parameter(Mandatory=$True)][string]$LogDir,
    [Switch]$ScheduleMode,
    [Switch]$LoadMode,
    [int]$SchedStart,
    [int]$SchedFinish,
    [int]$ThreshHoldLoad, #new
    [int]$CapacityBuffer, #new
    [int]$MinNumberAvail, #new
    [int]$ThresholdPowerOff, #new
    [Parameter(Mandatory=$True)][string]$DGName,
    [string]$BaseTag,
    [string]$IgnoreTag,
    #[ValidateSet($True,$False)]
    [Switch]$AWS,
    [String]$AWSProfile,
    [Switch]$OnPrem,
    [Switch]$Azure,
    [Switch]$Weekend,
    [Switch]$LogOnly,
    [Switch]$Email,
    [String]$SMTPserver,
    [string]$ToAddress,
    [string]$FromAddress
)

Clear-Host
#Import-Module AWSPowerShell
Add-PSSnapIn citrix*

##### Defines log path ####
$firstcomp = Get-Date
$filename = $firstcomp.month.ToString() + "-" + $firstcomp.day.ToString() + "-" + $firstcomp.year.ToString() + "-" + $firstcomp.hour.ToString() + "-" + $firstcomp.minute.ToString() + ".txt"
$outputloc = $LogDir + "\" + $filename
##### Defines log path ####

$hostname = hostname

Start-Transcript -Path $outputloc

############ Function Schedule Based ###########
Function Get-IntelliMode
    {
        If ($ScheduleMode -or $LoadMode)
            {
                $CurrentHour = get-date -format HH
                Try
                    {
                        $machines = Get-BrokerDesktop -AdminAddress $DeliveryController -MaxRecordCount 10000 -DesktopGroupName $DGName
                        $DeliveryGroup = Get-BrokerDesktopGroup -AdminAddress $DeliveryController -Name $DGName
                    }
                Catch
                    {
                        Write-host 'Unable to run command Get-BrokerDesktop, check $DeliveryController and $DGName variables'
                        exit
                    }
                if ($Weekend) {$IsWeekend = (get-date).DayOfWeek | Where-Object {$_ -like 'Saturday' -or $_ -like 'Sunday'}}

                if ($ScheduleMode)
                    {
                        if ($SchedStart -le $CurrentHour -and $SchedFinish -ge $CurrentHour -and $IsWeekend -eq $null)
                        {
                            #write-host "In Business"
                            Enter-ScheduleIn($machines)
                        }
                        Else
                        {
                            #Write-host "Outside Business Hours"
                            Enter-ScheduleOut($machines)
                        }
                    }
                if ($LoadMode)
                    {
                        If ($DeliveryGroup.SessionSupport -like 'Multi*')
                            {
                                $machinesLoad = $machines | Where-Object {$_.Tags -notcontains $IgnoreTag -and $_.Tags -notcontains $BaseTag}
                                $totalload = [math]::Round(($machinesLoad.loadindex | Measure-Object -Sum).Sum / ($machinesLoad.InMaintenanceMode | Group-Object {$_.Name -eq 'False'} | Select-Object -ExpandProperty Count)/100)

                                if ($totalload -ilt $threshhold)
                                    {
                                        Enter-LoadModeRemoveCapacity($totalload,$machinesLoad)
                                    }
                                Else
                                    {
                                        Enter-LoadModeAddCapacity($totalload,$machinesLoad)
                                    }
                            }
                        If ($DeliveryGroup.SessionSupport -like 'Single*')
                            {
                                #Use $MinNumberAvail (default 2) and $CapacityBuffer (default 10%)
                                #$machinesLoad = $machines | Where-Object {$_.Tags -notcontains $IgnoreTag -and $_.Tags -notcontains $BaseTag}
                                #$totalload = [math]::Round($machinesLoad.AssociatedUserNames.count / ($machinesLoad.InMaintenanceMode | Group-Object {$_.Name -eq 'False'} | Select-Object -ExpandProperty Count)*100)
                                

                            }
                    }
            }
        Else
            {
                Write-host "Please choose a mode paraemter: -ScheduleMode or -LoadMode"
            }
    }
############ End Function Schedule Based ###########

Function Enter-ScheduleIn
    {
        Write-host "******************************************"
        Write-host "Bussiness Hours"
        $machinesIn = $machines | Where-Object {$_.Tags -notcontains $IgnoreTag -and $_.Tags -notcontains $BaseTag}
        if ($machinesIn)
            {
                Write-Host "Working on Machines:"
                $machinesIn | Format-Table MachineName,DesktopGroupName,LoadIndex,RegistrationState,InMaintenanceMode,Tags
                Foreach ($machineIn in $machinesIn)
                    {
                        #Maintenance Mode
                        Write-host $machineIn.DNSName.Split(".",2)[0] "(Setting Maintenance Mode - FALSE)"
                        if (!($LogOnly))
                            {
                                Try
                                    {
                                        $machineIn | Set-BrokerMachine -InMaintenanceMode $False | Out-Null
                                    }
                                Catch
                                    {
                                        Write-host $machineIn.DNSName.Split(".",2)[0]  "(Unable to put machine in Maintenance Mode)"
                                    }
                            }
                        #Power On machines
                        if ($OnPrem)
                            {
                                Write-host "OnPrem"
                                If ($machineIn.powerstate -eq 'Off')
                                    {
                                        Write-Host $machineIn.DNSName.Split(".",2)[0] "(Starting Machine)"
                                        if (!($LogOnly))
                                            {
                                                Try
                                                    {
                                                        New-BrokerHostingPowerAction -AdminAddress $DeliveryController -Action TurnOn -MachineName $machineIn.HostedMachineName | Out-Null
                                                    }
                                                Catch
                                                    {
                                                        Write-Host $machineIn.DNSName.Split(".",2)[0] "(Unable to Start OnPrem Instance)"
                                                    }
                                            }
                                    }
                                Else
                                    {
                                        Write-host $machineIn.DNSName.Split(".",2)[0] "(Already Powered On)"
                                    }
                            }
                        if ($AWS)
                            {
                                Write-host "AWS"
                                Try
                                    {
                                        $instance = Get-EC2Instance -ProfileName $AWSProfile | Where-Object {$_.Instances.Tag.value -match $machineIn.DNSName.Split(".",2)[0]}
                                        if ($instance.instances.state.Name -eq 'stopped')
                                            {
                                                Write-Host $machineIn.DNSName.Split(".",2)[0] $instance.instances.instanceid "(Starting Machine)"
                                                if (!($LogOnly))
                                                    {
                                                        Try
                                                            {
                                                                Start-EC2Instance -ProfileName $AWSProfile -InstanceId $instance.Instances.instanceid | Out-Null
                                                            }
                                                        Catch
                                                            {
                                                                Write-Host $machineIn.DNSName.Split(".",2)[0] $instance.Instances.instanceid "(Unable to Start AWS Instance)"
                                                            }
                                                    }
                                            }
                                        Else
                                            {
                                                Write-Host $machineIn.DNSName.Split(".",2)[0] "(Already Powered On - AWS)"
                                            }
                                    }
                                Catch
                                    {
                                        Write-Host $machineIn.DNSName.Split(".",2)[0] "(Unable to Get AWS Instance)"
                                    }
                            }
                        if ($Azure)
                            {
                                Write-host "Azure"
                                Write-Host $machineIn.DNSName.Split(".",2)[0] "(Starting Machine)"
                                if (!($LogOnly))
                                    {
                                        Try
                                            {
                                                #Needs work
                                            }
                                        Catch
                                            {
                                                Write-Host $machineIn.DNSName.Split(".",2)[0] "(Unable to Get/Start Azure Instance)"
                                            }
                                    }
                            }
                    }
            }
        Else
            {
                Write-host "No machines to work with Inside Business hours, Check Tags"
            }
    }

Function Enter-ScheduleOut
    {
        Write-host "Outside Business Hours"

        $machinesOut = $machines | Where-Object {$_.Tags -notcontains $IgnoreTag -and $_.Tags -notcontains $BaseTag}
        if ($machinesOut)
            {
                Write-Host "Working on Machines:"
                $machinesOut | Format-Table MachineName,DesktopGroupName,LoadIndex,RegistrationState,InMaintenanceMode,Tags
                Foreach ($machineOut in $machinesOut)
                    {
                        #Maintenance Mode
                        Write-host $machineOut.DNSName.Split(".",2)[0] "(Setting Maintenance Mode - TRUE)"
                        if (!($LogOnly))
                            {
                                Try
                                    {
                                        $machineOut | Set-BrokerMachine -InMaintenanceMode $True | Out-Null
                                    }
                                Catch
                                    {
                                        Write-host $machineOut.DNSName.Split(".",2)[0] "(Unable to put Machine in Maintenance Mode)"
                                    }
                            }
                        #Power Off Machines
                        if ((Get-BrokerDesktop -AdminAddress $DeliveryController $machineOut.MachineName).InMaintenanceMode -eq 'True' -and !($machineOut.AssociatedUserNames))
                            {
                                if ($OnPrem)
                                    {
                                        Write-Host "OnPrem"
                                        Write-host $machineOut.DNSName.Split(".",2)[0] "(Powering off Machine)"
                                        if (!($LogOnly))
                                            {
                                                Try
                                                    {
                                                        New-BrokerHostingPowerAction -AdminAddress $DeliveryController -Action Shutdown -MachineName $machineOut.HostedMachineName | Out-Null
                                                    }
                                                Catch
                                                    {
                                                        Write-host $machineOut.DNSName.Split(".",2)[0] "(Unable to Power Off Machine)"
                                                    }
                                            }
                                    }
                                if ($AWS)
                                    {
                                        Write-Host "AWS"
                                        Try
                                            {
                                                $instance = Get-EC2Instance -ProfileName $AWSProfile | Where-Object {$_.Instances.Tag.value -match $machineOut.DNSName.Split(".",2)[0]}
                                                if ($instance.instances.state.Name -eq 'running')
                                                    {
                                                        Write-host $machineOut.DNSName.Split(".",2)[0] $Instance.instances.instanceid "(Powering off Machine)"
                                                        if (!($LogOnly))
                                                            {
                                                                Try
                                                                    {
                                                                        Stop-EC2Instance -ProfileName $AWSProfile -InstanceId $instance.Instances.instanceid | Out-Null
                                                                    }
                                                                Catch
                                                                    {
                                                                        Write-Host $instance.instances.tag.value $Instance.instances.instanceid "(Unable to Stop Instance)"
                                                                    }
                                                            }
                                                    }
                                                Else
                                                    {
                                                        Write-Host $machineOut.DNSName.Split(".",2)[0] "(Already Powered Down - AWS)"
                                                    }
                                            }
                                        Catch
                                            {
                                                Write-Host $machineOut.DNSName.Split(".",2)[0] "(Unable to Get Instance)"
                                            }
                                    }
                                if ($Azure)
                                    {
                                        Write-Host "Azure"
                                        Write-host $machineOut.DNSName.Split(".",2)[0] "(Powering off Machine)"
                                        If (!($LogOnly))
                                            {
                                                #Needs work
                                            }
                                    }
                            }
                        else
                            {
                                Write-host $machineOut.DNSName.Split(".",2)[0] "(User/s logged on or Can't put Machine in MAINT mode, cannot Power Off Machine)"
                            }
                    }
            }
        Else
            {
                Write-host "No machines to work with Outside of Business hours, Check Tags"
            }
    }

Function Enter-LoadModeRemoveCapacity
    {
        Write-host "Enter LoadMode Remove"

        $machinesLoad = $machines | Where-Object {$_.Tags -notcontains $IgnoreTag -and $_.Tags -notcontains $BaseTag}
        if ($machinesLoad)
            {
                Write-Host "Working on Machines:"
                $machinesLoad | Format-Table MachineName,DesktopGroupName,LoadIndex,RegistrationState,InMaintenanceMode,Tags
                Foreach ($machineLoad in $machinesLoad)
                    {
                        
                    }
            }
    }

    Function Enter-LoadModeAddCapacity
    {
        Write-host "Enter LoadMode Add"

        $machinesLoad = $machines | Where-Object {$_.Tags -notcontains $IgnoreTag -and $_.Tags -notcontains $BaseTag}
        if ($machinesLoad)
            {
                Write-Host "Working on Machines:"
                $machinesLoad | Format-Table MachineName,DesktopGroupName,LoadIndex,RegistrationState,InMaintenanceMode,Tags
                Foreach ($machineLoad in $machinesLoad)
                    {
                        
                    }
            }
    }

############ Email SMTP ###########
Function Email
    {
        $results = (Get-Content -Path $outputloc -raw)
        $smtpserver = $SMTPserver
        $msg = New-Object Net.Mail.MailMessage
        $smtp = New-Object net.Mail.SmtpClient($smtpserver)
        $msg.From = $FromAddress
        $msg.To.Add($ToAddress)
        $msg.Subject = "**Citrix IntelliScale Report - $DGName**"
        $msg.body = "$results"
        #$msg.Attachments.Add($att)
        $smtp.Send($msg)
    }
############ END Email SMTP ###########


###### Call out Functions ############

Get-IntelliMode

Write-host "-"
Write-host "******************************************"


###### End Call out Functions ############

####################### Closing ###########
$lastcomp = Get-date
$diff = ($lastcomp - $firstcomp)

Write-Host This Script took $diff.Minutes minutes and $diff.Seconds seconds to complete.
Write-Host "This Script Runs every hour from server: ($hostname)"
Write-host "******************************************"

Stop-Transcript
##############################################################

if ($Email) {Email}
