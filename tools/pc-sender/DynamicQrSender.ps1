# DynamicQr sender: shows images as an animated, fountain-coded QR code for the DynamicQr phone app.
# Usually started through send.bat (drag images onto it, or double-click for a file picker).
# Runs on stock Windows PowerShell 5.1 / .NET Framework 4; nothing to install.
[CmdletBinding(PositionalBinding = $false)]
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
    $enc = [DynamicQr.FrameEncoder]::new($Bundle, $BlockSize, [uint32](Get-TransferId))
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Count; $i++) { [void]$sb.Append($enc.FrameText([uint32]$i)).Append("`n") }
    $full = [System.IO.Path]::GetFullPath($Path)
    [System.IO.File]::WriteAllText($full, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllBytes($full + '.bundle', $Bundle)
    Write-Host ("Wrote {0} frames (K = {1}) to {2}" -f $Count, $enc.K, $full)
}

function Show-SenderWindow([byte[]]$Bundle, [int]$FileCount) {
    Write-Host 'The animation window is added in the next step.'
}

Import-SenderCode

if ($SelfTest) {
    if ([DynamicQr.SelfTest]::Run()) { exit 0 } else { exit 1 }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Select-ImageFiles {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Choose images to send to the phone'
    $dlg.Multiselect = $true
    $dlg.Filter = 'Images|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tif;*.tiff|All files|*.*'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return @() }
    return @($dlg.FileNames)
}

if (-not $Files -or $Files.Count -eq 0) {
    $Files = Select-ImageFiles
    if ($Files.Count -eq 0) { Write-Host 'Nothing selected.'; exit 0 }
}

$entries = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,byte[]]]'
$taken = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($path in $Files) {
    $name = [System.IO.Path]::GetFileName($path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Host "Skipped ${name}: not a file"; continue }
    if (-not [DynamicQr.ImagePrep]::IsSupported($path)) { Write-Host "Skipped ${name}: unsupported format"; continue }
    try {
        $full = (Resolve-Path -LiteralPath $path).ProviderPath
        $jpeg = [DynamicQr.ImagePrep]::Prepare($full, $MaxSide, [long]$Quality)
    } catch {
        Write-Host "Skipped ${name}: cannot read image ($($_.Exception.InnerException.Message))"
        continue
    }
    $outName = [DynamicQr.ImagePrep]::OutputName($full, $taken)
    $img = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(, $jpeg)))
    Write-Host ('{0,-40} {1,5}x{2,-5} {3,6:N0} KB' -f $outName, $img.Width, $img.Height, ($jpeg.Length / 1KB))
    $img.Dispose()
    $entries.Add((New-Object 'System.Collections.Generic.KeyValuePair[string,byte[]]' -ArgumentList $outName, $jpeg))
}
if ($entries.Count -eq 0) { Write-Host 'No images to send.'; exit 1 }

$bundle = [DynamicQr.BundleWriter]::Pack($entries)
$k = [Math]::Ceiling($bundle.Length / $BlockSize)
Write-Host ('Bundle: {0:N0} KB, K = {1} blocks, ~{2} s at {3} fps' -f ($bundle.Length / 1KB), $k, [Math]::Ceiling($k * 1.15 / $Fps), $Fps)

if ($DumpFrames -gt 0) {
    if (-not $Out) { throw '-DumpFrames needs -Out <file>' }
    Write-DumpFrames $bundle $DumpFrames $Out
    exit 0
}

Show-SenderWindow $bundle $entries.Count
exit 0
