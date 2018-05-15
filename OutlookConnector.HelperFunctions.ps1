﻿# Helper functions used within Outlook Connector module
# Functions are not exported out of module

function Trim-Length {
    param(
        [parameter(ValueFromPipeline=$True)][string] $Str,
        [parameter(Mandatory=$true,Position=1)][ValidateRange(1,[int]::MaxValue)][int] $Length
    )
    ($Str.TrimStart()[0..($Length-1)] -join "").TrimEnd()
}

function Get-ValidFileName {
    # reference
    # https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247%28v=vs.85%29.aspx?f=255&MSPPError=-2147217396
    # https://gallery.technet.microsoft.com/scriptcenter/Save-Email-from-Outlook-to-3abf1ff3#content
    
    param([Parameter(Mandatory=$true)][String]$FileName)

    # removing illegal characters
    foreach ($char in ([System.IO.Path]::GetInvalidFileNameChars())) {$FileName = $FileName.Replace($char, '_')}

    # trimming spaces and dots
    $FileName = $FileName -replace '(^[\s\.]+)|([\s\.]+$)', ''

    # return value
    $FileName
}

function New-Folder {
    # creates new folder if not existing
    param([Parameter(Mandatory=$true)][String]$TargetFolder)

    if (!(Test-Path -Path $TargetFolder)) {
        try {
            New-Item -ItemType Directory -Path $TargetFolder -ErrorAction Stop | Out-Null
        } catch {
            throw "Target folder $TargetFolder can't be created."
        }
    }
}

function Get-Properties {
    # get list of properties from provided pattern
    param(
        [Parameter(Mandatory=$true)][String]$FileNameFormat
    )
    $RegEx = '(?:\%)(.+?)(?:(?:\|)(.*?))?(?:\%)'
    [regex]::Matches($FileNameFormat,$RegEx) | ForEach-Object { $_.Groups[1].Value }
}

function Validate-Properties {
    # verifies if sent object has all needed properties
    # it returns $null if everything is fine, or list of missing properties
    # it should be used as if (Validate-Properties) {there are errors} else {no errors}
    param(
        [Parameter(Mandatory=$true)][psobject]$InputObject,
        [Parameter(Mandatory=$true)][String[]]$RequiredProperties
    )
    $ObjectProperties = ($InputObject | Get-Member).Name
    $NotFound = @()

    foreach ($Prop in $RequiredProperties) {
        if ($Prop -notin $ObjectProperties) {
            $NotFound += $Prop
        }
    }

    $NotFound
}

function Report-MissingProperties {
    param(
        [Parameter(Mandatory=$true)][psobject]$InputObject,
        [String[]]$MissingProperties
    )
    if ($MissingProperties.Length -gt 0) {
        $MessageType = $Message.MessageClass -replace '^IPM\.' # E-mail messages are IPM.Note, other possible types are IPM.Appointment, IPM.Task, IPM.Contact, etc.
        if ($MessageType -eq "Note") { $MessageType = "E-mail" }
        if ($Message.Subject) { # TODO Simplify this section
            $ErrorMessage = 'Message "' + $Message.Parent.FolderPath + '\' + $Message.Subject + '" of type ' + $MessageType + ' is not proper object.'
        } elseif ($MessageType) {
            $ErrorMessage = 'Message of type ' + $MessageType + ' is not proper object.'
        } else {
            $ErrorMessage = 'Message is not proper object.'
        }
        $ErrorMessage += ' Missing: ' + ($MissingProperties -join ',')
        if ($SkippedMessages) {
            $SkippedMessages.Value += $Message # adding skipped messages to referenced variable if passed
        }
        Write-Error -Message $ErrorMessage
    }
}

function Create-FileName {
    # generates file name based on provided pattern and object
    # replaces each property in pattern specified with %PropertyName|format% with value of Property from sent object
    # calling function should verify that all properties exist
    # filename has NO extension
    param(
        [Parameter(Mandatory=$true)][psobject]$InputObject,
        [Parameter(Mandatory=$true)][String]$FileNameFormat
    )
    $RegEx = '(?:\%)(.+?)(?:(?:\|)(.*?))?(?:\%)'

    $FileName = $FileNameFormat
    while ($FileName -match $RegEx) {
        $match = $Matches[0]
        $property = $Matches[1]
        if ($Matches.Count -ge 3) {
            $format = $Matches[2]
        } else {
            $format = ""
        }
        if ($format -match '^[\d]+$') { # if format is just an integer value then treat it as max length
            $FileName = $FileName.Replace($match, ($InputObject.($property) | Trim-Length $format))
        } else {
            $FileName = $FileName.Replace($match, "{0:$format}" -f $InputObject.($property))
        }
    }

    # return value
    $FileName
}

function Add-Numbering {
    # generates file name based on send file name and extension
    # if file with that name exists, it will add numbering like (1), (2), etc. at the end of name
    # file name should be full path name
    # example Add-Numbering 'C:\tmp\Name' 'msg'

    param(
        [Parameter(Mandatory=$true)][psobject]$FileName,
        [Parameter(Mandatory=$true)][String]$FileExtension
    )

    $i = 0
    $FullFilePath = $FileName + '.' + $FileExtension
    
    # Check if file exists, and if yes, update name with numbering
    while (Test-Path -LiteralPath $FullFilePath) {
        $FullFilePath = $FileName + ' (' + (++$i) + ').' + $FileExtension
    }

    $FullFilePath
}