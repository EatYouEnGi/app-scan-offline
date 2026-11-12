<#
.SYNOPSIS
    Tự động đẩy mã nguồn lên GitHub, kích hoạt GitHub Actions build cả Android (.apk) và iOS (.ipa),
    theo dõi tiến trình và tải cả 2 gói cài đặt về thư mục .\dist trên máy tính.
#>

param(
    [string]$RepoUrl = "",
    [string]$RepoName = "app-scan-offline",
    [switch]$Public = $false
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "=== [App Scan Cloud Builder] Tự động Build Android (.apk) & iOS (.ipa) trên GitHub Actions ===" -ForegroundColor Cyan

if ($RepoUrl -ne "") {
    if (git remote | Select-String -Pattern "^origin$") {
        git remote set-url origin $RepoUrl
    } else {
        git remote add origin $RepoUrl
    }
    Write-Host "Đang đẩy mã nguồn lên $RepoUrl (nhánh main)..." -ForegroundColor Yellow
    git push -u origin main
    Write-Host "Đã đẩy thành công! GitHub Actions đang tự động chạy workflow '.github/workflows/build.yml'." -ForegroundColor Green
    exit 0
}

# Nếu không truyền RepoUrl, sử dụng GitHub CLI (gh) để tạo repo, đẩy code, chờ build xong và tải file .apk + .ipa về máy
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghCmd) {
    $ghDefault = "C:\Program Files\GitHub CLI\gh.exe"
    if (Test-Path $ghDefault) {
        $env:PATH = "C:\Program Files\GitHub CLI;$env:PATH"
        $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    }
}

if (-not $ghCmd) {
    Write-Host "Đang cài đặt GitHub CLI (gh) qua winget..." -ForegroundColor Yellow
    winget install --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements
    $env:PATH = "C:\Program Files\GitHub CLI;$env:PATH"
}

# Kiểm tra đăng nhập GitHub
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Vui lòng xác thực tài khoản GitHub trên trình duyệt..." -ForegroundColor Yellow
    gh auth login --hostname github.com --git-protocol https --web
}

$visibility = if ($Public) { "--public" } else { "--private" }
if (-not (git remote | Select-String -Pattern "^origin$")) {
    Write-Host "Đang tạo kho chứa GitHub '$RepoName' ($visibility) và đẩy mã nguồn..." -ForegroundColor Cyan
    gh repo create $RepoName $visibility --source=. --remote=origin --push
} else {
    Write-Host "Đang đẩy mã nguồn lên origin/main..." -ForegroundColor Cyan
    git push -u origin main
}

Write-Host "Đang đợi GitHub Actions khởi chạy workflow build Android (.apk) & iOS (.ipa)..." -ForegroundColor Yellow
Start-Sleep -Seconds 6

$runId = gh run list --workflow=build.yml --limit 1 --json databaseId --jq ".[0].databaseId"
if ($runId) {
    Write-Host "Đang theo dõi tiến trình Build Cloud (Run ID: $runId)..." -ForegroundColor Cyan
    gh run watch $runId --exit-status

    $distDir = Join-Path $ProjectRoot "dist"
    New-Item -ItemType Directory -Force -Path $distDir | Out-Null
    Write-Host "Đang tải gói cài đặt Android (.apk) và iOS (.ipa) về $distDir ..." -ForegroundColor Cyan
    gh run download $runId --dir $distDir
    Write-Host "Hoàn tất! File cài đặt nằm tại: $distDir" -ForegroundColor Green
}

