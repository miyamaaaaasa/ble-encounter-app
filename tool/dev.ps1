# tool/dev.ps1 — 開発ワンコマンド集
# 使い方: pwsh tool/dev.ps1 <check|bump|build|deploy|logs|changelog|cycle> [serial]
param(
    [Parameter(Mandatory = $true)][string]$Cmd,
    [string]$Serial = ""
)
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Get-Devices {
    if ($Serial) { return @($Serial) }
    adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" } |
        ForEach-Object { ($_ -split "\t")[0] }
}

function Invoke-Check {
    Write-Host "== flutter analyze ==" -ForegroundColor Cyan
    if (-not (Test-Path ".dart_tool\package_config.json")) {
        Write-Host "(.dart_tool missing -> pub get)" -ForegroundColor Yellow
        flutter pub get | Out-Null
    }
    $out = flutter analyze 2>&1
    $errors = $out | Select-String " error "
    if ($errors) { $errors; Write-Host "NG: errors found" -ForegroundColor Red; exit 1 }
    Write-Host "OK: no errors" -ForegroundColor Green
}

function Invoke-Bump {
    $pub = Get-Content pubspec.yaml -Raw -Encoding utf8
    if ($pub -match "version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)") {
        $new = "version: $($Matches[1]).$($Matches[2]).$([int]$Matches[3]+1)+$([int]$Matches[4]+1)"
        $pub = $pub -replace "version:\s*\d+\.\d+\.\d+\+\d+", $new
        [IO.File]::WriteAllText("$Root\pubspec.yaml", $pub, (New-Object Text.UTF8Encoding $false))
        Write-Host "bumped -> $new (表示は beta 付き)" -ForegroundColor Green
    } else { Write-Host "version line not found" -ForegroundColor Red; exit 1 }
}

function Invoke-Build {
    Write-Host "== build apk --release ==" -ForegroundColor Cyan
    $out = flutter build apk --release 2>&1
    if ($out | Select-String "mergeReleaseNativeLibs|Failed to delete") {
        # Windowsのファイルロック定番エラー → クリーンして1回だけ再試行
        Write-Host "known lock error -> clean retry" -ForegroundColor Yellow
        Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
        $out = flutter build apk --release 2>&1
    }
    # 注意: "√"はcp932コンソールで化けるためASCIIパターンのみで判定する
    $ok = $out | Select-String "Built build"
    if ($ok) { Write-Host "OK: $ok" -ForegroundColor Green }
    else { $out | Select-String "Error|FAILED" | Select-Object -First 10; exit 1 }
}

function Invoke-Deploy {
    $apk = "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $apk)) { Write-Host "APK not found. run build first" -ForegroundColor Red; exit 1 }
    foreach ($d in Get-Devices) {
        Write-Host "== deploy -> $d ==" -ForegroundColor Cyan
        adb -s $d install -r $apk
        adb -s $d shell am start -n com.example.ble_encounter/.MainActivity | Out-Null
    }
}

function Invoke-Logs {
    foreach ($d in Get-Devices) {
        Write-Host "== logs: $d ==" -ForegroundColor Cyan
        Write-Host "--- crashes ---" -ForegroundColor Yellow
        adb -s $d logcat -d 2>$null | Select-String "FATAL EXCEPTION|AndroidRuntime" | Select-Object -Last 5
        Write-Host "--- flutter (last 15) ---" -ForegroundColor Yellow
        adb -s $d logcat -d -s flutter 2>$null | Select-Object -Last 15
    }
}

function Invoke-Changelog {
    $ver = (Select-String -Path pubspec.yaml -Pattern "^version: (.+)$").Matches[0].Groups[1].Value
    $log = git log --pretty=format:"%ad|%s" --date=short
    $lines = @("# CHANGELOG", "", "Current: beta$ver", "")
    foreach ($l in $log) {
        $d, $s = $l -split "\|", 2
        if ($s -match "^beta[\d.]+") { $lines += "## $s  ($d)" } else { $lines += "- $s  ($d)" }
    }
    $lines -join "`n" | Set-Content CHANGELOG.md -Encoding utf8
    Write-Host "CHANGELOG.md regenerated" -ForegroundColor Green
}

function Invoke-Test {
    Write-Host "== flutter test (回帰スイート) ==" -ForegroundColor Cyan
    $out = flutter test 2>&1
    $last = $out | Select-Object -Last 1
    if ($last -match "All tests passed") { Write-Host "OK: $last" -ForegroundColor Green }
    else { $out | Select-Object -Last 15; Write-Host "NG: tests failed" -ForegroundColor Red; exit 1 }
}

function Invoke-Release {
    # Phase2: Version更新→PubGet→Analyze→Test→Build→CHANGELOG→Commit→Push→APK出力
    # コミットメッセージ: -Serial 引数を流用しない。$env:RELEASE_MSG か自動生成。
    Invoke-Bump
    flutter pub get | Out-Null
    Invoke-Check
    Invoke-Test
    Invoke-Build
    Invoke-Changelog
    $ver = (Select-String -Path pubspec.yaml -Pattern "^version: (.+)$").Matches[0].Groups[1].Value
    $msg = if ($env:RELEASE_MSG) { "beta${ver}: $env:RELEASE_MSG" } else { "beta${ver}: release build" }
    $tmp = New-TemporaryFile
    "$msg`n`nCo-Authored-By: Claude <noreply@anthropic.com>" | Set-Content $tmp -Encoding utf8
    git add -A
    git commit -F $tmp.FullName
    git push origin main
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $apk = Resolve-Path "build\app\outputs\flutter-apk\app-release.apk"
    Write-Host "RELEASE DONE: beta$ver" -ForegroundColor Green
    Write-Host "APK: $apk"
}

switch ($Cmd) {
    "check"     { Invoke-Check }
    "test"      { Invoke-Test }
    "bump"      { Invoke-Bump }
    "build"     { Invoke-Build }
    "deploy"    { Invoke-Deploy }
    "logs"      { Invoke-Logs }
    "changelog" { Invoke-Changelog }
    "cycle"     { Invoke-Check; Invoke-Test; Invoke-Bump; Invoke-Build; Invoke-Deploy; Start-Sleep 6; Invoke-Logs }
    "release"   { Invoke-Release }
    default     { Write-Host "usage: dev.ps1 <check|test|bump|build|deploy|logs|changelog|cycle|release> [serial]`n  release: `$env:RELEASE_MSG='summary' を設定するとコミットメッセージに反映" }
}
