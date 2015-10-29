[CmdletBinding()]
param (
    [Parameter(Mandatory=1)][string]$SharePath="",
    [Parameter(Mandatory=1)][string]$IncludeSettings="",
    [Parameter(Mandatory=1)][string]$IncludeData="",
    [Parameter(Mandatory=0)][string]$ExcludeSettings="",
    [Parameter(Mandatory=0)][string]$ExcludeData="",
    [Parameter(Mandatory=0)][string]$LogPath=""
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName "System.IO.Compression.FileSystem"

#region ## Logging ##
if(!$LogPath){
    if(Test-Path $env:USERPROFILE -PathType Container){
        $LogFile = Get-ChildItem $PSCommandPath | ForEach-Object{Write-Output $(($env:USERPROFILE)+'\'+($_.BaseName)+"_$env:USERNAME"+'.log')}
    } else {throw "Could not find a valid log path."}
} else {
    if(Test-Path $LogPath -PathType Container){
        $LogFile = Get-ChildItem $PSCommandPath | ForEach-Object{Write-Output $((Get-ChildItem $LogPath).DirectoryName[0]+'\'+($_.BaseName)+"_$env:USERNAME"+'.log')}
    } else {throw "Log path not found."}
}
if(!(Test-Path $LogFile -PathType Leaf)){(Get-Date).ToString() + ' Log file created.' > $LogFile}
#endregion Logging

#region ## Constants ##
$CMPATH = 'CM Profiles'
$CMPROFILEPATH = "$SharePath\$CMPATH\$env:USERNAME"
$CMREGPATH = "$CMPROFILEPATH"
$CMREGFILE = 'ntuser.reg'
$CMDATAPATH = "$CMPROFILEPATH"

$AMPATH = 'AM Profiles'
$AMPROFILEPATH = "$SharePath\$AMPATH\$env:USERNAME"
$AMREG = "$env:USERNAME"+'_settings'
$AMREGZIP = "$AMREG"+'.zip'
$AMREGPATH = "$AMPROFILEPATH\$AMREGZIP"
$AMREGFILE = '*.reg'
$AMDATA = "$env:USERNAME"+'_data'
$AMDATAZIP = "$AMDATA"+'.zip'
$AMDATAPATH = "$AMPROFILEPATH\$AMDATAZIP"
$TMPSUFFIX = (Get-Date).Subtract((Get-Date -Date '1/1/2012')).Ticks
$AMLOCALTMP = "$env:USERPROFILE\"+'AMProfileTmp'+"$TMPSUFFIX"
$AMLOCALREGZIP = "$AMLOCALTMP\$AMREGZIP"
$AMLOCALREGPATH = "$AMLOCALTMP\$AMREG"
$AMLOCALDATAZIP = "$AMLOCALTMP\$AMDATAZIP"
$AMLOCALDATAPATH = "$AMLOCALTMP\$AMDATA"
#endregion Constants

#region ## Functions ##
function Append-Log([string]$msg){(Get-Date).ToString() + " $msg" >> $LogFile}
function Die([string]$msg){Append-Log $msg; throw $msg}
function CleanUp-Session(){
    if(Test-Path $AMLOCALTMP -PathType Container){Remove-Item $AMLOCALTMP -Recurse -WhatIf} ##REMOVE whatif for production
}
function Unzip-File(){
    param([string]$Path,[string]$Destination)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Path,$Destination)
}
function Validate-Params(){
    $SharePath = $SharePath.TrimEnd('\')

    $Params = '' | Select-Object SharePath,IncludeSettings,IncludeData,ExcludeSettings,ExcludeData,LogPath
    $Params.SharePath = $SharePath
    $Params.IncludeSettings = $IncludeSettings
    $Params.IncludeData = $IncludeData
    $Params.ExcludeSettings = $ExcludeSettings
    $Params.ExcludeData = $ExcludeData
    $Params.LogPath = $LogPath
    Append-Log "Validating params: $Params"

    if(!(Test-Path $SharePath -PathType Container)){Die 'Aborting. Remote user profile path not found.'}
    if(!(Test-Path $SharePath\$AMPATH -PathType Container) -or !(Test-Path $SharePath\$CMPATH -PathType Container)){Die 'Aborting. Invalid profile path. Check constants.'}
    if(!(Test-Path $IncludeSettings -PathType Leaf)){Die 'Aborting. Settings include file not found.'}
    if(!(Test-Path $IncludeData -PathType Leaf)){Die 'Aborting. Data include file not found.'}
    if($ExcludeSettings -and !(Test-Path $ExcludeSettings -PathType Leaf)){Die 'Aborting. Settings exclude file not found.'}
    if($ExcludeData -and !(Test-Path $ExcludeData -PathType Leaf)){Die 'Aborting. Data exclude file not found.'}
}
function Get-UserProfile(){
    Append-Log 'Searching for user profile.'
    $UP = '' | Select-Object Type,SettingsPath,DataPath,Reg
    if(Test-Path "$CMPROFILEPATH" -PathType Container){
        # Citrix UPM
        Append-Log 'Found Citrix UPM profile.'
        if(!(Test-Path "$CMREGPATH\$CMREGFILE" -PathType Leaf)){Die 'Aborting. Reg file not found.'}
        $UP.Type = 'CM'
        $UP.SettingsPath = Get-ChildItem "$CMREGPATH\$CMREGFILE"
        $UP.DataPath = Get-ChildItem -Recurse "$CMDATAPATH"
    } else {
        if(Test-Path "$AMPROFILEPATH" -PathType Container){
            # Autometrix
            Append-Log 'Found Autometrix profile.'
            if(!(Test-Path "$AMREGPATH" -PathType Leaf)){Die 'Aborting. Settings file not found.'}
            if(!(Test-Path "$AMDATAPATH" -PathType Leaf)){Die 'Aborting. Data file not found.'}

            try{# to copy Autometrix profile locally
                New-Item "$AMLOCALTMP" -ItemType directory -Force | Out-Null
                Copy-Item -Path "$AMREGPATH" -Destination "$AMLOCALTMP"
                Copy-Item -Path "$AMDATAPATH" -Destination "$AMLOCALTMP"
                Unzip-File -Path "$AMLOCALREGZIP" -Destination "$AMLOCALREGPATH"
                Unzip-File -Path "$AMLOCALDATAZIP" -Destination "$AMLOCALDATAPATH"
            }catch{
                Append-Log $_.Exception.ItemName
                Append-Log $_.Exception.Message
                CleanUp-Session
                Die 'Aborting.'
            }
            $UP.Type = 'AM'
            $UP.SettingsPath = Get-ChildItem "$AMLOCALREGPATH" -Include "$AMREGFILE" -Recurse
            $UP.DataPath = Get-ChildItem -Recurse "$AMLOCALDATAPATH"
        } else {
            # FS-Logix
            Append-Log 'Profile not found.'
            Append-Log 'User has already been migrated.'
            $UP.Type = 'FS'
        }
    }
    $UP
}
function Get-Settings(){
    param([Parameter(ValueFromPipeline=$true)][psobject]$UP)         ##HERE do stuff!
    try{
        Write-Host 'testing'
        $UP
    }catch{
        Append-Log $_.Exception.ItemName
        Append-Log $_.Exception.Message
        CleanUp-Session
        Die 'Aborting.'
    }
}
function Get-Data(){
    param([Parameter(ValueFromPipeline=$true)][psobject]$UP)
    try{
        
    }catch{
        Append-Log $_.Exception.ItemName
        Append-Log $_.Exception.Message
        CleanUp-Session
        Die 'Aborting.'
    }
}
function Include-Settings(){
    param([Parameter(ValueFromPipeline=$true)][psobject]$UP)
    try{
        
    }catch{
        Append-Log $_.Exception.ItemName
        Append-Log $_.Exception.Message
        CleanUp-Session
        Die 'Aborting.'
    }
}
function Include-Data(){
    param([Parameter(ValueFromPipeline=$true)][psobject]$UP)
    try{
        
    }catch{
        Append-Log $_.Exception.ItemName
        Append-Log $_.Exception.Message
        CleanUp-Session
        Die 'Aborting.'
    }
}
function Exclude-Settings(){
    param([Parameter(ValueFromPipeline=$true)][psobject]$UP)
    try{
        
    }catch{
        Append-Log $_.Exception.ItemName
        Append-Log $_.Exception.Message
        CleanUp-Session
        Die 'Aborting.'
    }
}
function Exclude-Data(){
    param([Parameter(ValueFromPipeline=$true)][psobject]$UP)
    try{
        
    }catch{
        Append-Log $_.Exception.ItemName
        Append-Log $_.Exception.Message
        CleanUp-Session
        Die 'Aborting.'
    }
}
function Set-Settings(){
    param([Parameter(ValueFromPipeline=$true)][psobject]$UP)
    try{
        
    }catch{
        Append-Log $_.Exception.ItemName
        Append-Log $_.Exception.Message
        CleanUp-Session
        Die 'Aborting.'
    }
}
function Set-Data(){
    param([Parameter(ValueFromPipeline=$true)][psobject]$UP)
    try{
        
    }catch{
        Append-Log $_.Exception.ItemName
        Append-Log $_.Exception.Message
        CleanUp-Session
        Die 'Aborting.'
    }
}
#endregion Functions

#region ## Main ##
Append-Log "Begin operation. User: $env:USERNAME on Computer: $env:COMPUTERNAME"
Validate-Params

$UserProfile = Get-UserProfile

$UserProfile | Get-Settings


<#
if($UserProfile.Type -ne 'FS'){
    $UserProfile | Get-Settings | Include-Settings | Exclude-Settings | Set-Settings
    $UserProfile | Get-Data | Include-Data | Exclude-Data | Set-Data
}
#>

#endregion Main

#region ## Cleanup ##
if($UserProfile.Type -eq 'AM'){CleanUp-Session}
Append-Log 'Operation completed successfully.'
Append-Log 'Exiting.'
#endregion Cleanup