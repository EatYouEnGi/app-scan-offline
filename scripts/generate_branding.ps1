# Tạo bộ tài nguyên thương hiệu ScanD (icon app, adaptive foreground, splash) từ assets/ScanD-V2-export
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'assets\ScanD-V2-export\ScanD-V2-icon.png'
$outDir = Join-Path $root 'assets\branding'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$navy = [System.Drawing.Color]::FromArgb(255, 15, 27, 61)
$icon = [System.Drawing.Bitmap]::FromFile($src)

function New-Canvas([int]$size, [bool]$fillNavy) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.PixelOffsetMode = 'HighQuality'
  if ($fillNavy) { $g.Clear($navy) } else { $g.Clear([System.Drawing.Color]::Transparent) }
  return @($bmp, $g)
}

# 1) Icon vuông full-bleed (iOS tự bo góc) - nền navy, giữ nguyên tỷ lệ thiết kế
$c = New-Canvas 1024 $true
$c[1].DrawImage($icon, 0, 0, 1024, 1024)
$c[0].Save((Join-Path $outDir 'scand_icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$c[1].Dispose(); $c[0].Dispose()

# 2) Adaptive foreground Android (vùng an toàn 66%) - nền trong suốt
$c = New-Canvas 1024 $false
$s = [int](1024 * 0.70); $o = [int]((1024 - $s) / 2)
$c[1].DrawImage($icon, $o, $o, $s, $s)
$c[0].Save((Join-Path $outDir 'scand_foreground.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$c[1].Dispose(); $c[0].Dispose()

# 3) Ảnh Splash (logo trung tâm, nền trong suốt để đặt trên nền navy)
$c = New-Canvas 768 $false
$s = 512; $o = [int]((768 - $s) / 2)
$c[1].DrawImage($icon, $o, $o, $s, $s)
$c[0].Save((Join-Path $outDir 'scand_splash.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$c[1].Dispose(); $c[0].Dispose()

# 4) Splash Android 12+ (icon bị mask tròn 2/3 -> thu nhỏ nội dung)
$c = New-Canvas 1152 $false
$s = 640; $o = [int]((1152 - $s) / 2)
$c[1].DrawImage($icon, $o, $o, $s, $s)
$c[0].Save((Join-Path $outDir 'scand_splash_android12.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$c[1].Dispose(); $c[0].Dispose()

# 5) Logo ngang cho màn Splash trong Flutter
Copy-Item (Join-Path $root 'assets\ScanD-V2-export\ScanD-V2-logo-on-dark.png') (Join-Path $outDir 'scand_logo_on_dark.png') -Force
Copy-Item $src (Join-Path $outDir 'scand_icon_rounded.png') -Force

$icon.Dispose()
Remove-Item (Join-Path $outDir 'scandoc_icon.png'), (Join-Path $outDir 'scandoc_foreground.png') -ErrorAction SilentlyContinue
Get-ChildItem $outDir | Select-Object Name, Length

