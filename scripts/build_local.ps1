<#
.SYNOPSIS
    Script tự động kiểm tra/cài đặt Flutter SDK cục bộ (tùy chọn), chạy bộ kiểm thử nghiệm thu
    30 mẫu chuẩn và đóng gói file APK Android đã ký (Signed Release APK) ngay trên Windows.
#>

param(
    [switch]$InstallFlutterIfMissing = $false
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "=== [App Scan Cá Nhân] Bắt đầu quy trình kiểm thử & Build ===" -ForegroundColor Cyan

# 1. Tìm kiếm Flutter SDK trên máy
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    $candidatePaths = @(
        "C:\src\flutter\bin\flutter.bat",
        "$env:USERPROFILE\flutter\bin\flutter.bat",
        "$env:LOCALAPPDATA\flutter\bin\flutter.bat"
    )
    foreach ($p in $candidatePaths) {
        if (Test-Path $p) {
            $env:PATH = "$(Split-Path -Parent $p);$env:PATH"
            $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
            break
        }
    }
}

if (-not $flutterCmd) {
    if ($InstallFlutterIfMissing) {
        $targetDir = "$env:USERPROFILE\flutter"
        Write-Host "Đang tải Flutter SDK (nhánh stable) về $targetDir ..." -ForegroundColor Yellow
        git clone https://github.com/flutter/flutter.git -b stable $targetDir
        $env:PATH = "$targetDir\bin;$env:PATH"
    } else {
        Write-Host "Chưa tìm thấy Flutter SDK trên máy Windows này." -ForegroundColor Yellow
        Write-Host "-> Cách 1: Chạy lại lệnh: .\scripts\build_local.ps1 -InstallFlutterIfMissing" -ForegroundColor Green
        Write-Host "-> Cách 2: Đẩy mã nguồn lên GitHub để GitHub Actions (.github/workflows/build.yml) tự động build cả APK Android và IPA iOS trên đám mây." -ForegroundColor Green
        exit 0
    }
}

# 2. Khởi tạo các tệp wrapper còn thiếu nhưng giữ nguyên mã nguồn native tùy chỉnh
$tempAndroid = Join-Path $env:TEMP "appscan_android_backup"
if (Test-Path $tempAndroid) { Remove-Item $tempAndroid -Recurse -Force }
Copy-Item -Path "$ProjectRoot\android" -Destination $tempAndroid -Recurse

flutter create . --platforms=android,ios --org com.appscan.offline --project-name app_scan
Copy-Item -Path "$tempAndroid\*" -Destination "$ProjectRoot\android" -Recurse -Force

# 3. Tải gói phụ thuộc và chạy kiểm thử nghiệm thu
flutter pub get
flutter test test/scanner_acceptance_test.dart

# 4. Tạo keystore ký APK nếu chưa có
$keystoreFile = "$ProjectRoot\android\app\release-key.jks"
$keyPropsFile = "$ProjectRoot\android\key.properties"
if (-not (Test-Path $keystoreFile)) {
    $keytoolCmd = Get-Command keytool -ErrorAction SilentlyContinue
    if ($keytoolCmd) {
        Write-Host "Đang tạo khóa ký APK cá nhân (release-key.jks)..." -ForegroundColor Cyan
        keytool -genkey -v `
            -keystore $keystoreFile `
            -keyalg RSA -keysize 2048 -validity 10000 `
            -alias appscan_key `
            -storepass appscan2026 `
            -keypass appscan2026 `
            -dname "CN=App Scan Personal, OU=Mobile, O=Personal, L=Hanoi, S=HN, C=VN"

        @"
storePassword=appscan2026
keyPassword=appscan2026
keyAlias=appscan_key
storeFile=release-key.jks
"@ | Set-Content -Path $keyPropsFile -Encoding UTF8
    }
}

# 5. Đóng gói APK Release
flutter build apk --release
Write-Host "Hoàn tất! Tệp APK tại: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green

