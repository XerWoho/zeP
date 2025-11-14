if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
	$argString = $args -join ' '
	Start-Process powershell -Verb runAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $argString"
	exit
}

$localAppData = "C:/Users/Public/AppData/Local/"
$zepDir = Join-Path $localAppData "zeP/"
$zepZigDir = Join-Path $zepDir "zig/"
$zepZigExeDir = Join-Path $zepZigDir "e/"
$zepZigExe = Join-Path $zepZigExeDir "zig.exe"

# Create directories if they don't exist
New-Item -Path $zepDir -ItemType Directory -Force | Out-Null
New-Item -Path $zepZigDir -ItemType Directory -Force | Out-Null
New-Item -Path $zepZigExeDir -ItemType Directory -Force | Out-Null

$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if (-not ($machinePath.Split(';') -contains $zepZigExeDir)) {
	$machineNewPath = $zepZigExeDir + ";" + $machinePath
	[Environment]::SetEnvironmentVariable("Path", $machineNewPath, "Machine")
	Write-Host "$zepZigExeDir added to user PATH. You may need to restart your terminal to see the change."
}
else {
	Write-Host "$zepZigExeDir is already in the PATH."
}

if ($args.Length -eq 0) {
	exit
}

$target = $args[0]
if (Test-Path $zepZigExe) { Remove-Item $zepZigExe -Force }
New-Item -ItemType SymbolicLink -Target $target -Path $zepZigExe | Out-Null  # zigExe is the symlink