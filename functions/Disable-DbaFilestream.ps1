function Disable-DbaFileStream {
    <#
    .SYNOPSIS
        Sets the status of FileStream on specified SQL Server instances both at the server level and the instance level

    .DESCRIPTION
        Connects to the specified SQL Server instances, and sets the status of the FileStream feature to the required value

        To perform the action, the SQL Server instance must be restarted. By default we will prompt for confirmation for this action, this can be overridden with the -Force switch

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Credential
        Login to the target server using alternative credentials.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Restart SQL Instance after changes. Use this parameter with care as it overrides whatif.

    .PARAMETER WhatIf
        Shows what would happen if the command runs. The command is not run unless Force is specified.

    .PARAMETER Confirm
        Prompts you for confirmation before running the command.

    .NOTES
        Tags: Filestream
        Author: Stuart Moore ( @napalmgram ) | Chrissy LeMaire ( @cl )
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        Disable-DbaFileStream -SqlInstance server1\instance2 -FileStreamLevel T-Sql Only
        Disable-DbaFileStream -SqlInstance server1\instance2 -FileStreamLevel 1

        These commands are functionally equivalent, both will set Filestream level on server1\instance2 to T-Sql Only

    .EXAMPLE
        Get-DbaFileStream -SqlInstance server1\instance2, server5\instance5 , prod\hr | Where-Object {$_.FileSteamStateID -gt 0} | Disable-DbaFileStream -FileStreamLevel 0 -Force

        Using this pipeline you can scan a range of SQL instances and disable filestream on only those on which it's enabled

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [DbaInstance[]]$SqlInstance,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$SqlCredential,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        $FileStreamLevel = $level = 0

        $OutputLookup = @{
            0 = 'Disabled'
            1 = 'FileStream enabled for T-Sql access'
            2 = 'FileStream enabled for T-Sql and IO streaming access'
            3 = 'FileStream enabled for T-Sql, IO streaming, and remote clients'
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure connecting to $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            # Instance level
            $filestreamstate = [int]$server.Configuration.FilestreamAccessLevel.RunningValue
            
            if ($Force -or $PSCmdlet.ShouldProcess($instance, "Changing from '$($OutputLookup[$filestreamstate])' to '$($OutputLookup[$level])' at the instance level")) {
                try {
                    $null = Set-DbaSpConfigure -SqlInstance $server -Name FilestreamAccessLevel -Value $level -EnableException
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
            
            # Server level
            if ($server.IsClustered) {
                $nodes = Get-DbaWsfcNode -ComputerName $instance -Credential $Credential
                foreach ($node in $nodes.Name) {
                    $result = Set-FileSystemSetting -Instance $node -Credential $Credential -FilestreamLevel $FileStreamLevel
                }
            } else {
                $result = Set-FileSystemSetting -Instance $instance -Credential $Credential -FilestreamLevel $FileStreamLevel
            }
            
            if ($Force) {
                $restart = Restart-DbaService -ComputerName $instance.ComputerName -InstanceName $server.ServiceName -Type Engine -Force
            }
            
            Get-DbaFilestream -SqlInstance $instance -SqlCredential $SqlCredential -Credential $Credential

            if ($filestreamstate -ne $level -and -not $Force) {
                Write-Message -Level Warning -Message "[$instance] $result"
            }
        }
    }
}