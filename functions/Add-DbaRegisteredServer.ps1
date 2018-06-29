﻿#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Add-DbaRegisteredServer {
    <#
        .SYNOPSIS
            Adds registered servers to SQL Server Central Management Server (CMS).

        .DESCRIPTION
            Adds registered servers to SQL Server Central Management Server (CMS).

        .PARAMETER SqlInstance
            The target SQL Server instance

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER ServerName
            Specifies one or more server names to include. Server Name is the actual SQL instance name (labeled Server Name)
    
        .PARAMETER Name
            Specifies one or more names to include. Name is basically the nickname in SSMS CMS interface (labeled Registered Server Name)

        .PARAMETER Group
            Specifies one or more groups to include from SQL Server Central Management Server.

        .PARAMETER InputObjects
            Allows results from Get-DbaRegisteredServer to be piped in

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Chrissy LeMaire (@cl)
            Tags: RegisteredServer, CMS

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Add-DbaRegisteredServer

        .EXAMPLE
           Add-DbaRegisteredServer -SqlInstance sql2008 -ServerName sql01 -Name "The 2008 Clustered Instance" -Description "HR's Dedicated SharePoint instance"

           Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, "The 2008 Clustered Instance" will be visible.
           Clearly this is hard to explain ;) 

        .EXAMPLE
            Add-DbaRegisteredServer -SqlInstance sql2012, sql2014 -Group HR -ServerName sql01

            Creates a registered server on sql2012 and sql2014's CMS for sql01, nicknamed sql01, with no description
    
        .EXAMPLE
            Get-DbaRegisteredServerGroup -SqlInstance sql2012 -Group HR | Add-DbaRegisteredServer -ServerName sql01

            Creates a registered server on sql2012's CMS for sql01, nicknamed sql01
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$ServerName,
        [string]$Name = $ServerName,
        [string]$Description,
        [object]$Group,
        [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject,
        [switch]$EnableException
    )
    
    process {
        foreach ($instance in $SqlInstance) {
            if ((Test-Bound -ParameterName Group)) {
                if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    $InputObject += $Group
                }
                else {
                    $InputObject += Get-DbaRegisteredServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                }
            }
            else {
                $InputObject += Get-DbaRegisteredServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
            }
        }
        
        foreach ($reggroup in $InputObject) {
            $parentserver = Get-RegServerParent -InputObject $reggroup
            
            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
            }
            
            $server = $parentserver.ServerConnection.SqlConnectionObject
            
            if ($Pscmdlet.ShouldProcess($reggroup.Parent, "Adding $reggroup")) {
                try {
                    $newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($reggroup, $Name)
                    $newserver.ServerName = $ServerName
                    $newserver.Description = $Description
                    $newserver.Create()
                    
                    Get-DbaRegisteredServer -SqlInstance $server -Name $Name -ServerName $ServerName
                }
                catch {
                    Stop-Function -Message "Failed to add $ServerName on $($parentserver.SqlInstance)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}