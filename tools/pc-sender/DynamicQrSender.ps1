# DynamicQr sender: shows images as an animated, fountain-coded QR code for the DynamicQr phone app.
# Usually started through send.bat (drag images onto it, or double-click for a file picker).
# Runs on stock Windows PowerShell 5.1 / .NET Framework 4; nothing to install.
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Files,
    [int]$MaxSide = 1280,
    [int]$Quality = 80,
    [int]$BlockSize = 800,
    [int]$Fps = 8,
    [ValidateSet('L', 'M')][string]$Ecc = 'L',
    [int]$DumpFrames = 0,
    [string]$Out,
    [string]$TransferId,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Import-SenderCode {
    $qrDll = Join-Path $PSScriptRoot 'lib\QRCoder.dll'
    [void][System.Reflection.Assembly]::LoadFrom($qrDll)
    Add-Type -AssemblyName System.Drawing, System.Windows.Forms
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Filter '*.cs' | ForEach-Object { $_.FullName })
    Add-Type -LiteralPath $sources -ReferencedAssemblies @('System.Drawing', 'System.Windows.Forms', 'System.Core', $qrDll)
}

function Get-TransferId {
    if ($TransferId) { return [Convert]::ToUInt32($TransferId, 16) }
    $bytes = New-Object byte[] 4
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

# Writes the first $Count frame texts (one per line, UTF-8 without BOM, LF) and the raw bundle to "$Path.bundle".
function Write-DumpFrames([byte[]]$Bundle, [int]$Count, [string]$Path) {
    $enc = New-Object DynamicQr.FrameEncoder -ArgumentList @(, $Bundle), $BlockSize, (Get-TransferId)
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Count; $i++) { [void]$sb.Append($enc.FrameText([uint32]$i)).Append("`n") }
    $full = [System.IO.Path]::GetFullPath($Path)
    [System.IO.File]::WriteAllText($full, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllBytes($full + '.bundle', $Bundle)
    Write-Host ("Wrote {0} frames (K = {1}) to {2}" -f $Count, $enc.K, $full)
}

Import-SenderCode

if ($SelfTest) {
    if ([DynamicQr.SelfTest]::Run()) { exit 0 } else { exit 1 }
}

Write-Host 'Image sending is added in the next step.'
exit 1
