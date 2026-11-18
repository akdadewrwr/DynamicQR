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
    [switch]$SelfTest,
    [switch]$FromCmdLine
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

# Splits the raw cmd.exe command line (env DQR_CMDLINE, set by send.bat) into the arguments that followed
# the .bat path. Quoted segments keep spaces; everything else (including & ^ ( ) [ ] ') is taken literally.
function Split-LauncherArgs([string]$CmdLine, [string]$BatPath) {
    $name = [System.IO.Path]::GetFileName($BatPath)
    $at = $CmdLine.IndexOf($BatPath, [System.StringComparison]::OrdinalIgnoreCase)
    $len = $BatPath.Length
    if ($at -lt 0) {
        $at = $CmdLine.IndexOf($name, [System.StringComparison]::OrdinalIgnoreCase)
        $len = $name.Length
    }
    if ($at -lt 0) { return @() }
    $rest = $CmdLine.Substring($at + $len)
    if ($rest.StartsWith('"')) { $rest = $rest.Substring(1) }
    $tokens = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inQuotes = $false
    foreach ($ch in $rest.ToCharArray()) {
        if ($ch -eq '"') { $inQuotes = -not $inQuotes; continue }
        if (-not $inQuotes -and [char]::IsWhiteSpace($ch)) {
            if ($sb.Length -gt 0) { $tokens.Add($sb.ToString()); [void]$sb.Clear() }
            continue
        }
        [void]$sb.Append($ch)
    }
    if ($sb.Length -gt 0) { $tokens.Add($sb.ToString()) }
    $clean = @($tokens | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    return , $clean
}

# Turns launcher tokens into named parameters for this script (array splatting would treat "-Fps" as a file).
function ConvertTo-SenderParams([string[]]$Tokens) {
    $switches = @('SelfTest')
    $valued = @('MaxSide', 'Quality', 'BlockSize', 'Fps', 'Ecc', 'DumpFrames', 'Out', 'TransferId')
    $params = @{}
    $fileList = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $t = $Tokens[$i]
        $name = if ($t.StartsWith('-')) { $t.Substring(1) } else { '' }
        $sw = @($switches | Where-Object { $_ -ieq $name })
        $val = @($valued | Where-Object { $_ -ieq $name })
        if ($sw.Count -eq 1) { $params[$sw[0]] = $true }
        elseif ($val.Count -eq 1 -and $i + 1 -lt $Tokens.Count) { $params[$val[0]] = $Tokens[++$i] }
        else { $fileList.Add($t) }
    }
    if ($fileList.Count -gt 0) { $params['Files'] = $fileList.ToArray() }
    return $params
}

if ($FromCmdLine) {
    $launcherParams = ConvertTo-SenderParams (Split-LauncherArgs $env:DQR_CMDLINE $env:DQR_BAT)
    & $PSCommandPath @launcherParams
    exit $LASTEXITCODE
}

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
    [DynamicQr.SenderForm]::EnableDpiAwareness()
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $enc = [DynamicQr.FrameEncoder]::new($Bundle, $BlockSize, [uint32](Get-TransferId))
    $level = [QRCoder.QRCodeGenerator+ECCLevel]::$Ecc
    $form = [DynamicQr.SenderForm]::new($enc, $Fps, $level, $FileCount, $Bundle.Length)
    Write-Host 'Showing the QR animation. Resize the window freely. Keys: + / - speed, Space pause, F11 full screen, Esc quit.'
    [System.Windows.Forms.Application]::Run($form)
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
