if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
	$argString = $args -join ' '
	Start-Process powershell -Verb runAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $argString"
	exit
}

$LocalAppData = "C:/Users/Public/AppData/Local/"
$ZepDir = Join-Path $LocalAppData "zeP/"
$ZepZigDir = Join-Path $ZepDir "zig/"
$ZepZigExeDir = Join-Path $ZepZigDir "e/"
$ZepZigExe = Join-Path $ZepZigExeDir "zig.exe"

# Create directories if they don't exist
New-Item -Path $ZepDir -ItemType Directory -Force | Out-Null
New-Item -Path $ZepZigDir -ItemType Directory -Force | Out-Null
New-Item -Path $ZepZigExeDir -ItemType Directory -Force | Out-Null

$UserPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if (-not ($UserPath.Split(';') -contains $ZepZigExeDir)) {
	$NewPath = $ZepZigExeDir + ";" + $UserPath
	[Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
	Write-Host "$ZepZigExeDir added to user PATH. You may need to restart your terminal to see the change."
}


if ($args.Length -eq 0) {
	exit
}

$Target = $args[0]
if (Test-Path $ZepZigExe) { Remove-Item $ZepZigExe -Force }
New-Item -ItemType SymbolicLink -Target $Target -Path $ZepZigExe | Out-Null  # zigExe is the symlink