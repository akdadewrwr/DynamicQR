# Regenerates entry/src/test/vectors/{frames.txt,bundle.bin}: frames written by this sender that the
# phone-side protocol tests (tools/protocol-tests/tests/vectors.test.ts) must decode exactly.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('dqr-vectors-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # 'a.png' 300x200 gradient
    $a = New-Object System.Drawing.Bitmap 300, 200
    for ($x = 0; $x -lt 300; $x++) { for ($y = 0; $y -lt 200; $y++) { $a.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(($x * 255 / 299), ($y * 255 / 199), 128)) } }
    $a.Save((Join-Path $work 'a.png'), [System.Drawing.Imaging.ImageFormat]::Png); $a.Dispose()

    # non-ASCII name: (U+6D4B U+8BD5) space (U+56FE U+7247) "(1).png", 240x240 with text
    $cnName = ([string][char]0x6D4B) + [char]0x8BD5 + ' ' + [char]0x56FE + [char]0x7247 + '(1).png'
    $b = New-Object System.Drawing.Bitmap 240, 240
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.Clear([System.Drawing.Color]::Bisque)
    $g.DrawString('DynamicQr', (New-Object System.Drawing.Font('Arial', 24)), [System.Drawing.Brushes]::DarkBlue, 10, 100)
    $g.Dispose()
    $b.Save((Join-Path $work $cnName), [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()

    # 'c.jpg' 200x300 stripes
    $c = New-Object System.Drawing.Bitmap 200, 300
    $g = [System.Drawing.Graphics]::FromImage($c)
    for ($i = 0; $i -lt 10; $i++) { $g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(25 * $i, 100, 255 - 25 * $i))), 0, 30 * $i, 200, 30) }
    $g.Dispose()
    $c.Save((Join-Path $work 'c.jpg'), [System.Drawing.Imaging.ImageFormat]::Jpeg); $c.Dispose()

    $vec = Join-Path $PSScriptRoot '..\..\entry\src\test\vectors'
    New-Item -ItemType Directory -Force -Path $vec | Out-Null
    $out = Join-Path (Resolve-Path $vec).ProviderPath 'frames.txt'
    $sender = Join-Path $PSScriptRoot 'DynamicQrSender.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sender -BlockSize 200 -TransferId 12345678 -DumpFrames 600 -Out $out `
        (Join-Path $work 'a.png') (Join-Path $work $cnName) (Join-Path $work 'c.jpg')
    if ($LASTEXITCODE -ne 0) { throw "sender failed with exit code $LASTEXITCODE" }
    Move-Item -Force -LiteralPath ($out + '.bundle') -Destination (Join-Path (Split-Path $out) 'bundle.bin')
    Write-Host "Vectors written to $(Split-Path $out)"
} finally {
    Remove-Item -Recurse -Force -LiteralPath $work
}
