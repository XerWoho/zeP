$Target = "0.5" # latest version
if (-not ($args.Length -eq 0)) {
    $Target = $args[0]
}


function Ensure-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Start-Process powershell -Verb runAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $Target"
        exit
    }
}
Ensure-Admin

$LocalAppData = "C:/Users/Public/AppData/Local/"
$ZepDir = Join-Path $LocalAppData "zeP/"
$ZepZigDir = Join-Path $ZepDir "zig/"
$TempZepZigDir = Join-Path $ZepDir "tmp/"
$TempZepZigFile = Join-Path $TempZepZigDir "$Target.zip"

$ManifestZep = Join-Path $ZepDir "zep/manifest.json"

$ExeZepDir = Join-Path $ZepDir "zep/e/"
$ExeZepFile = Join-Path $ExeZepDir "zeP.exe"

$ExeZigDir = Join-Path $ZepDir "zig/e/"



$DestZepZigDir = Join-Path $ZepDir "zep/v/$Target"
if (Test-Path $DestZepZigDir -PathType Container) {
    Remove-Item -Path $DestZepZigDir -Force -Recurse
}

$ZepTargetFile = Join-Path $DestZepZigDir "zeP.exe"

function Set-EnvVar {
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if (-not ($UserPath.Split(';') -contains $ExeZepDir)) {    
        $NewPath = $ExeZepDir + ";" + $UserPath
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
        Write-Host "$ExeZepDir added to user PATH. You may need to restart your terminal to see the change."
    }
    if (-not ($UserPath.Split(';') -contains $ExeZigDir)) {    
        $NewPath = $ExeZigDir + ";" + $UserPath
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
        Write-Host "$ExeZigDir added to user PATH. You may need to restart your terminal to see the change."
    }
}

function Set-Up {
    New-Item -Path $ZepDir -ItemType Directory -Force | Out-Null
    New-Item -Path $ZepZigDir -ItemType Directory -Force | Out-Null


    New-Item -Path $TempZepZigDir -ItemType Directory -Force | Out-Null
    New-Item -Path $TempZepZigFile -ItemType File -Force | Out-Null

    New-Item -Path $DestZepZigDir -ItemType Directory -Force | Out-Null
    New-Item -Path $ExeZepDir -ItemType Directory -Force | Out-Null

    New-Item -Path $ExeZigDir -ItemType Directory -Force | Out-Null

    New-Item -Path $ManifestZep -ItemType File -Force | Out-Null

    $data = @{
        version = "$Target"
        path = "$DestZepZigDir"
    }

    $data | ConvertTo-Json -Depth 10 | Set-Content "$ManifestZep"

    Set-EnvVar
}
Set-Up

function Get-Download {
    Invoke-WebRequest -uri "https://github.com/XerWoho/zeP/releases/download/$Target/windows_$Target.zip" -Method "GET"  -Outfile $TempZepZigFile
    Expand-Archive $TempZepZigFile -DestinationPath $DestZepZigDir
    Remove-Item -Path $TempZepZigDir -Force -Recurse
}
Get-Download


& "$ZepTargetFile" setup

if (Test-Path $ExeZepFile) { Remove-Item $ExeZepFile -Force }
New-Item -ItemType SymbolicLink -Target $ZepTargetFile -Path $ExeZepFile | Out-Null  # exeZep is the symlink

Read-Host "Installation finished!"
