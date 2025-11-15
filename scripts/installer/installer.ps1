if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
	$argString = $args -join ' '
	Start-Process powershell -Verb runAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $argString"
	exit
}


$localAppData = "C:/Users/Public/AppData/Local/"
$zepDir = Join-Path $localAppData "zeP/"
$zepZigDir = Join-Path $zepDir "zig/"

# Create directories if they don't exist
New-Item -Path $zepDir -ItemType Directory -Force | Out-Null
New-Item -Path $zepZigDir -ItemType Directory -Force | Out-Null


$tempZepZigDir = Join-Path $zepDir "tmp/"
New-Item -Path $tempZepZigDir -ItemType Directory -Force | Out-Null



$destZepZigDir = Join-Path $localAppData "zeP/v/0.1"
if (Test-Path $destZepZigDir -PathType Container) {
    Write-Host "Zep Version exists."
} else {
    New-Item -Path $destZepZigDir -ItemType Directory -Force | Out-Null
}


$exeZepDir = Join-Path $localAppData "zep/e"
$exeZepFile = Join-Path $localAppData "zep/e/zeP.exe"
if (Test-Path $exeZepDir -PathType Container) {
    Write-Host "Exe zep Dir exists."
} else {
    New-Item -Path $exeZepDir -ItemType Directory -Force | Out-Null
}
$userPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if (-not ($userPath.Split(';') -contains $exeZepDir)) {    
    $newPath = $exeZepDir + ";" + $userPath
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Write-Host "$exeZepDir added to user PATH. You may need to restart your terminal to see the change."
}



$tempZepZigFile = Join-Path $tempZepZigDir "0.1.zip"
New-Item -Path $tempZepZigFile -ItemType File -Force | Out-Null

Invoke-WebRequest -uri "https://github.com/XerWoho/zeP/releases/download/0.1/windows_0.1.zip" -Method "GET"  -Outfile $tempZepZigFile
Expand-Archive $tempZepZigFile -DestinationPath $destZepZigDir
Remove-Item -Path $tempZepZigDir -Force -Recurse

$tempZepPackagesFolder = Join-Path $destZepZigDir "packages"
$destZepPackagesFolder = Join-Path $zepDir "ava"
Move-Item -Path $tempZepPackagesFolder -Destination $destZepPackagesFolder


$tempZepScriptsFolder = Join-Path $destZepZigDir "scripts"
$destZepScriptsFolder = Join-Path $zepDir "scripts"
Move-Item -Path $tempZepScriptsFolder -Destination $destZepScriptsFolder


$zePTargetFile = Join-Path $destZepZigDir "zeP.exe"
& "$zePTargetFile" setup


if (Test-Path $exeZepFile) { Remove-Item $exeZepFile -Force }
New-Item -ItemType SymbolicLink -Target $zePTargetFile -Path $exeZepFile | Out-Null  # exeZep is the symlink

Read-Host "Press Enter to exit"
