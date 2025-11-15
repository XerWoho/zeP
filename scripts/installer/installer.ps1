if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
	$argString = $args -join ' '
	Start-Process powershell -Verb runAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $argString"
	exit
}

$localAppData = "C:/Users/Public/AppData/Local/"
$destZepZigDir = Join-Path $localAppData "zeP/v/0.1"
if (Test-Path $destZepZigDir -PathType Container) {
    Write-Host "Zep Version already exists."
    # exit
}

$zepDir = Join-Path $localAppData "zeP/"
$zepZigDir = Join-Path $zepDir "zig/"

$tempZepZigDir = Join-Path $zepDir "tmp/"
$tempZepZigFile = Join-Path $tempZepZigDir "0.1.zip"

$exeZepDir = Join-Path $zepDir "e/"
$exeZepFile = Join-Path $exeZepDir "zeP.exe"

function Set-EnvVar {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if (-not ($userPath.Split(';') -contains $exeZepDir)) {    
        $newPath = $exeZepDir + ";" + $userPath
        [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
        Write-Host "$exeZepDir added to user PATH. You may need to restart your terminal to see the change."
    }
}

function Set-Up {
    New-Item -Path $zepDir -ItemType Directory -Force | Out-Null
    New-Item -Path $zepZigDir -ItemType Directory -Force | Out-Null


    New-Item -Path $tempZepZigDir -ItemType Directory -Force | Out-Null
    New-Item -Path $tempZepZigFile -ItemType File -Force | Out-Null

    New-Item -Path $destZepZigDir -ItemType Directory -Force | Out-Null
    New-Item -Path $exeZepDir -ItemType Directory -Force | Out-Null

    Set-EnvVar
}


function Get-Download {
    Invoke-WebRequest -uri "https://github.com/XerWoho/zeP/releases/download/0.1/windows_0.1.zip" -Method "GET"  -Outfile $tempZepZigFile
    Expand-Archive $tempZepZigFile -DestinationPath $destZepZigDir
    Remove-Item -Path $tempZepZigDir -Force -Recurse
}


#####
###
# move the packages and scripts from
# the extracted folder, to the main 
# zeP folder
$tempZepPackagesFolder = Join-Path $destZepZigDir "packages"
$destZepPackagesFolder = Join-Path $zepDir "ava"
Move-Item -Path $tempZepPackagesFolder -Destination $destZepPackagesFolder
###
$tempZepScriptsFolder = Join-Path $destZepZigDir "scripts"
$destZepScriptsFolder = Join-Path $zepDir "scripts"
Move-Item -Path $tempZepScriptsFolder -Destination $destZepScriptsFolder
###
#####


$zePTargetFile = Join-Path $destZepZigDir "zeP.exe"
& "$zePTargetFile" setup

if (Test-Path $exeZepFile) { Remove-Item $exeZepFile -Force }
New-Item -ItemType SymbolicLink -Target $zePTargetFile -Path $exeZepFile | Out-Null  # exeZep is the symlink

Read-Host "Press Enter to exit"
