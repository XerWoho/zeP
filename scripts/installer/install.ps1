if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
	$argString = $args -join ' '
	Start-Process powershell -Verb runAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $argString"
	exit
}


$p = "C:/Users/Public/AppData/Local/"
$zBinDir = Join-Path $p "zeP/bin/"

$zDir = Join-Path $p "zeP/"
$zigDir = Join-Path $zDir "zig/"
$zigExe = Join-Path $zigDir "zig.exe"

# Create directories if they don't exist
New-Item -Path $zDir -ItemType Directory -Force | Out-Null
New-Item -Path $zigDir -ItemType Directory -Force | Out-Null



$tmpZDir = Join-Path $zDir "tmp/"
New-Item -Path $tmpZDir -ItemType Directory -Force | Out-Null

if (Test-Path $destZDir -PathType Container) {
    Write-Host "Folder exists."
}

$destZDir = Join-Path $p "zeP/v/0.1"
New-Item -Path $destZDir -ItemType Directory -Force | Out-Null

$zipFile = Join-Path $tmpZDir "0.1.zip"
New-Item -Path $zipFile -ItemType File -Force | Out-Null

Write-Host $zipFile

Invoke-WebRequest -uri "https://github.com/XerWoho/zeP/releases/download/pre/0.1.zip" -Method "GET"  -Outfile $zipFile
Expand-Archive $zipFile -DestinationPath $destZDir

Remove-Item -Path $tmpZDir -Force -Recurse

$userPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if (-not ($userPath.Split(';') -contains $destZDir)) {    
    $newPath = $destZDir + ";" + $userPath
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Write-Host "$destZDir added to user PATH. You may need to restart your terminal to see the change."
}

$packagesFolder = Join-Path $destZDir "packages"
$movePackages = Join-Path $zDir "ava"
Move-Item -Path $packagesFolder -Destination $movePackages


$scriptsFolder = Join-Path $destZDir "scripts"
$moveScripts = Join-Path $zDir "scripts"
Move-Item -Path $scriptsFolder -Destination $moveScripts
