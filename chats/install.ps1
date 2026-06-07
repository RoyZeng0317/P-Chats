# P Chats -- One-line setup for Windows (PowerShell 5.1+)
# Usage:
#   .\install.ps1               -- setup only
#   .\install.ps1 -Run          -- setup + run
#   .\install.ps1 -BuildAndroid -- setup + build APK
#   .\install.ps1 -BuildWindows -- setup + build .exe
param(
    [switch]$Run,
    [switch]$BuildAndroid,
    [switch]$BuildWindows
)

$ErrorActionPreference = 'Stop'
$PROJECT = 'p-chats-26652'

function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green  }
function Warn($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [XX] $m" -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host '  P Chats -- Windows Setup' -ForegroundColor Cyan
Write-Host ''

# 1. Flutter
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Fail 'Flutter SDK not found. Install from https://flutter.dev/docs/get-started/install'
}
Ok ('Flutter: ' + ((flutter --version 2>&1)[0]))

# 2. Firebase CLI
if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Warn 'Firebase CLI not found -- installing via npm...'
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Fail 'npm not found. Install Node.js from https://nodejs.org'
    }
    npm install -g firebase-tools
}
Ok ('Firebase CLI: ' + (firebase --version 2>&1))

# 3. flutter pub get
Ok 'Installing Flutter packages...'
flutter pub get
if ($LASTEXITCODE -ne 0) { Fail 'flutter pub get failed' }

# 3b. Generate app icons
Ok 'Generating app icons...'
dart run flutter_launcher_icons
if ($LASTEXITCODE -ne 0) { Warn 'Icon generation failed (non-fatal)' }

# 4. Firebase login check
$loginOutput = (firebase login:list 2>&1) -join ' '
if ($loginOutput -notmatch '@') {
    Warn 'Not logged in to Firebase -- opening browser...'
    firebase login
}

# 5. Deploy Firestore rules
Ok 'Deploying Firestore security rules...'
firebase deploy --only firestore:rules --project $PROJECT
if ($LASTEXITCODE -ne 0) { Fail 'Firestore rules deploy failed' }

Write-Host ''
Write-Host '  Setup complete!' -ForegroundColor Green
Write-Host ''

# 6. Optional action
if ($Run) {
    Ok 'Starting app...'
    flutter run
}
elseif ($BuildAndroid) {
    Ok 'Building Android APK...'
    flutter build apk --release
    Ok 'APK saved to: build\app\outputs\flutter-apk\app-release.apk'
}
elseif ($BuildWindows) {
    Ok 'Building Windows EXE...'
    flutter build windows --release
    Ok 'EXE saved to: build\windows\x64\runner\Release\'
}
else {
    Write-Host '  Next steps:'
    Write-Host '    flutter run                       -- debug on connected device'
    Write-Host '    .\install.ps1 -BuildAndroid       -- release APK'
    Write-Host '    .\install.ps1 -BuildWindows       -- release EXE'
    Write-Host ''
}
