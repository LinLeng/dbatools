﻿#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Stop-Function {
    <#
        .SYNOPSIS
            Function that interrupts a function.

        .DESCRIPTION
            Function that interrupts a function.

            This function is a utility function used by other functions to reduce error catching overhead.
            It is designed to allow gracefully terminating a function with a warning by default and also allow opt-in into terminating errors.
            It also allows simple integration into loops.

            Note:
            When calling this function with the intent to terminate the calling function in non-EnableException mode too, you need to add a return below the call.

        .PARAMETER Message
            A message to pass along, explaining just what the error was.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER Category
            What category does this termination belong to?
            Mandatory so long as no inner exception is passed.

        .PARAMETER ErrorRecord
            An option to include an inner exception in the error record (and in the exception thrown, if one is thrown).
            Use this, whenever you call Stop-Function in a catch block.

            Note:
            Pass the full error record, not just the exception.

        .PARAMETER FunctionName
            The name of the function to crash.
            This parameter is very optional, since it automatically selects the name of the calling function.
            The function name is used as part of the errorid.
            That in turn allows easily figuring out, which exception belonged to which function when checking out the $error variable.

        .PARAMETER Target
            The object that was processed when the error was thrown.
            For example, if you were trying to process a Database Server object when the processing failed, add the object here.
            This object will be in the error record (which will be written, even in non-EnableException mode, just won't show it).
            If you specify such an object, it becomes simple to actually figure out, just where things failed at.

        .PARAMETER Exception
            Allows specifying an inner exception as input object. This will be passed on to the logging and used for messages.
            When specifying both ErrorRecord AND Exception, Exception wins, but ErrorRecord is still used for record metadata.

        .PARAMETER OverrideExceptionMessage
            Disables automatic appending of exception messages.
            Use in cases where you already have a speaking message interpretation and do not need the original message.

        .PARAMETER Continue
            This will cause the function to call continue while not running silently.
            Useful when mass-processing items where an error shouldn't break the loop.

        .PARAMETER SilentlyContinue
            This will cause the function to call continue while running silently.
            Useful when mass-processing items where an error shouldn't break the loop.

        .PARAMETER ContinueLabel
            When specifying a label in combination with "-Continue" or "-SilentlyContinue", this function will call continue with this specified label.
            Helpful when trying to continue on an upper level named loop.

        .EXAMPLE
            Stop-Function -Message "Foo failed bar!" -EnableException $EnableException -ErrorRecord $_
            return

            Depending on whether $EnableException is true or false it will:
            - Throw a bloody terminating error. Game over.
            - Write a nice warning about how Foo failed bar, then terminate the function. The return on the next line will then end the calling function.

        .EXAMPLE
            Stop-Function -Message "Foo failed bar!" -EnableException $EnableException -Category InvalidOperation -Target $foo -Continue

            Depending on whether $silent is true or false it will:
            - Throw a bloody terminating error. Game over.
            - Write a nice warning about how Foo failed bar, then call continue to process the next item in the loop.
            In both cases, the error record added to $error will have the content of $foo added, the better to figure out what went wrong.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(DefaultParameterSetName = 'Plain')]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $Message,

        [bool]
        [Alias('Silent')]
        $EnableException = $EnableException,

        [Parameter(ParameterSetName = 'Plain')]
        [Parameter(ParameterSetName = 'Exception')]
        [System.Management.Automation.ErrorCategory]
        $Category = ([System.Management.Automation.ErrorCategory]::NotSpecified),

        [Parameter(ParameterSetName = 'Exception')]
        [Alias('InnerErrorRecord')]
        [System.Management.Automation.ErrorRecord[]]
        $ErrorRecord,

        [string]
        $FunctionName = ((Get-PSCallStack)[0].Command),

        [object]
        $Target,

        [System.Exception]
        $Exception,

        [switch]
        $OverrideExceptionMessage,

        [switch]
        $Continue,

        [switch]
        $SilentlyContinue,

        [string]
        $ContinueLabel
    )

    #region Handle Input Objects
    if ($Target) {
        $targetType = $Target.GetType().FullName

        switch ($targetType) {
            "Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter" { $targetToAdd = $Target.InstanceName }
            "Microsoft.SqlServer.Management.Smo.Server" { $targetToAdd = ([Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter]$Target).InstanceName }
            default { $targetToAdd = $Target }
        }
        if ($targetToAdd.GetType().FullName -like "Microsoft.SqlServer.Management.Smo.*") { $targetToAdd = $targetToAdd.ToString() }
    }
    #endregion Handle Input Objects

    $records = @()

    if ($ErrorRecord -or $Exception) {
        if ($ErrorRecord) {
            foreach ($record in $ErrorRecord) {
                if (-not $Exception) {
                    $innermessage = Get-ErrorMessage -Record $record
                    $newException = New-Object System.Exception($innermessage, $record.Exception)
                }
                else {
                    $newException = $Exception
                }
                if ($record.CategoryInfo.Category) { $Category = $record.CategoryInfo.Category }
                $records += New-Object System.Management.Automation.ErrorRecord($newException, "dbatools_$FunctionName", $Category, $targetToAdd)
            }
        }
        else {
            $records += New-Object System.Management.Automation.ErrorRecord($Exception, "dbatools_$FunctionName", $Category, $targetToAdd)
        }

        # Manage Debugging
        Write-Message -Level Warning -Message $Message -EnableException $EnableException.ToBool() -FunctionName $FunctionName -Target $targetToAdd -ErrorRecord $records -OverrideExceptionMessage:$OverrideExceptionMessage
    }
    else {
        $exception = New-Object System.Exception($Message)
        $records += New-Object System.Management.Automation.ErrorRecord($Exception, "dbatools_$FunctionName", $Category, $targetToAdd)

        # Manage Debugging
        Write-Message -Level Warning -Message $Message -EnableException $EnableException.ToBool() -FunctionName $FunctionName -Target $targetToAdd -ErrorRecord $records -OverrideExceptionMessage:$true
    }



    #region EnableException Mode
    if ($EnableException) {
        if ($SilentlyContinue) {
            foreach ($record in $records) { Write-Error -Message $record -Category $Category -TargetObject $targetToAdd -Exception $record.Exception -ErrorId "dbatools_$FunctionName" -ErrorAction Continue }
            if ($ContinueLabel) { continue $ContinueLabel }
            else { Continue }
        }

        # Extra insurance that it'll stop
        Set-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 1 -Value $true

        throw $records[0]
    }
    #endregion EnableException Mode

    #region Non-EnableException Mode
    else {
        # This ensures that the error is stored in the $error variable AND has its Stacktrace (simply adding the record would lack the stacktrace)
        foreach ($record in $records) {
            $null = Write-Error -Message $record -Category $Category -TargetObject $targetToAdd -Exception $record.Exception -ErrorId "dbatools_$FunctionName" -ErrorAction Continue 2>&1
        }

        if ($Continue) {
            if ($ContinueLabel) { continue $ContinueLabel }
            else { Continue }
        }
        else {
            # Make sure the function knows it should be stopping
            Set-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 1 -Value $true

            return
        }
    }
    #endregion Non-EnableException Mode
}