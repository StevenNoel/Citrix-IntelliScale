# Citrix-IntelliScale
This script can be used to intelligently power up/down machines on prem or in the cloud (AWS,Azure,GCP) based upon time 'schedule' or 'load'.

Tested with XA/XD 7.15LTSR and 7.18, however this should work with pretty much all 7.x versions.

Note: 
1) Use the -LogOnly option to run the script in Log Only mode, which doesn't take any actions on any machines.
2) Only -AWS and -OnPrem parameters works right now. -Azure is still being written
3) Only -ScheduleLoad parameter works right now, -LoadMode is still being written

# Prerequisites
1) You can run this on a Delivery Controller or a machine that has Studio installed.  See link for more information: https://developer-docs.citrix.com/projects/delivery-controller-sdk/en/latest/?_ga=2.136519158.731763323.1530151703-1594485461.1522783813#use-the-sdk 
3) Run Under a domain account that is a Cirix Farm Administrator
4) Run as a Scheduled Task

## For AWS:
1) AWS Tools for Powershell - https://aws.amazon.com/powershell/
2) Launch Powershell AWS Tools as admin
3) Set-AWSCredentials -AccessKey asdfasdf -SecretKey asdfasdfasdfasdfasdf -StoreAs My-AWS-Credentials
4) Get-AWSCredential -ListProfileDetail (to confirm you have a profile now)

## For Azure:
Still being worked on

# Parameters
-LogDir : This is the output director for logging.  Also used by the -Email paraemter

-ScheduleMode : This puts the script in 'Schedule Mode'

-SchedStart : Used with -ScheduleMode, this tells the script what time to Start Powering UP machines. (military time format)

-SchedFinish : Used with -ScheduleMode, this tells the script what time to Start Powering DOWN machines. (military time format)

-LoadMode : This puts the script in 'Load Mode'.  This hasn't been written yet.

-DeliveryController : This is the Citrix Delivery Controller

-DGName : This is the Delivery Group Name you are targeting

-BaseTag : This is a Citrix Tag assigned to VDAs that you don't want the script to touch.  Used to denote machines that are always on

-IgnoreTag : This is a Citrix Tag used to specify a machine that you don't want to be included in the script.

-AWS : Used to denote that the script will use Power Up/Down actions via AWS CLI

-AWSProfile : Used in conjunction with -AWS.  This tells the AWS CLI what set of credentials to use. (See prerequisite for setup)

-OnPrem : Used to denote that script will use Power Up/Down actions via Citrix Broker commands

-Azure : Used to denote that script will use Power Up/Down actions via Azure CLI

-Weekend : Used to with -SchedMode to Enter the Enter-ScheduleOut Function if the day is a Saturday or Sunday, regardless of time.

-LogOnly : Puts the script in Audit Mode.  It will report everything that it should do, but won't take any action.

-Email : Denotes that it will email the results

-SMTPserver : SMTP server

-ToAddress : Email To

-FromAddress: Email From

# Modes
The two different modes are 'ScheduleMode' and 'LoadMode'.  The only working mode right now is 'ScheduleMode'.  I hope to develop the 'LoadMode' over time.

## ScheduleMode
This mode parameter -ScheduleMode is also followed by -SchedStart and -SchedFinish parameters.  These take a number related to time (military format) you want the script to perform actions.  Example -SchedStart 6 -SchedFinish 16, This tells the script that during 6AM-4PM to perform actions (keep things out of maintenance mode and powered on).  Anything outside those hours starts to put machines in maintenance mode and shutdown if no users are logged in.

This mode is designed to be run as a scheduled task every hour, 30 minutes, 15 minutes, etc...

## LoadMode
This mode hasn't ben written yet.  The idea here is to more dynamically look at the load on all servers and power up/down machines based upon that, no matter what time of day.

# Functions
## Function Get-IntelliMode
This Function will understand what mode you want, by looking at parameters used.  This will include determining if -ScheduleMode or -LoadMode is used. If -ScheduleMode is used, it looks at -SchedStart and -SchedFinish times to determine if it's inside those timeframes or Outside.

## Function Enter-ScheduleIn
This Function is used for -ScheduleMode mode.  If we are using -SchedStart 6AM and -SchedFinish 16, we are saying to Start at 6 and Finish at 4PM. So if it is 11AM and the script starts, it will arrive at this function.  While in the function it works on machines that are in a certain Delivery Group (defined by -DGName parameter).  It will ignore the -BaseTag Tagged VDAs and -IgnoreTag tagged VDAs.  Once it has it's machine list, it will make sure "maintenance mode" is set to FALSE and Power UP the machine, if shut down.

## Function Enter-ScheduleOut
This Function is used for -ScheduleMode mode.  If we are using -SchedStart 6AM and -SchedFinish 16, we are saying to Start at 6 and Finish at 4PM. So if it is 9PM and the script starts, it will arrive at this function.  While in the function it works on machines that are in a certain Delivery Group (defined by -DGName parameter).  It will ignore the -BaseTag Tagged VDAs and -IgnoreTag tagged VDAs.  Once it has it's machine list, it will make sure "maintenance mode" is set to TRUE and Power DOWN the machine, if no users are logged on.

# Examples
```
& '.\(Name of Script).ps1' -DeliveryController Citrix-ddc1 -LogDir C:\temp -ScheduleMode -SchedStart 6 -SchedFinish 16 -DGName DG-Server2012R2 -BaseTag Base -OnPrem -LogOnly
```
This script will look at the dlivery group 'DG-Server2012R2' on the Delivery Controller 'Citrix-ddc1'.  It's using the mode 'ScheduleMode' which powers up/down machines based upon Times set in 'SchedStart' and 'SchedFinish' (military time).  At 'SchedStart', it makes sure machines are powered on and available for connections all the way up to the 'SchedFinish' time.  The 'BaseTag' Base is
used to denote that these machines won't get controlled in this script.  These are your base machines that you don't want power managed.  The 'OnPrem' paraemter is notifying the script to use certain commands geared for on premesis deployments.  Lastly we are using the 'LogOnly' parameter to put the script in an audit mode. So it will report everything, but won't actually execute the action.
```
& '.\(Name of Script).ps1' -DeliveryController Citrix-ddc1 -LogDir C:\temp -ScheduleMode -SchedStart 6 -SchedFinish 16 -DGName DG-Server2012R2 -BaseTag Base -IgnoreTag UnIntelli -AWS -AWSProfile My-AWS-Credentials -SMTPserver smtp.domain.local -ToAddress Steve@asdf.com -FromAddress Steve@asdf.com -Email
```
This script performs like above, but is geared for AWS deployments, with the -AWS parameter.  It also ignores any VDAs tagged with 'UnIntelli' tag.  It uses the AWS Credential Profile 'AWSProfile' called My-AWS-Credentials.  Lastly it emails the results to the defined email addresses.
```
