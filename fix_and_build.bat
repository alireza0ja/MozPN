@echo off
echo Setting Flutter China mirror...
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

echo Cleaning Flutter project...
call flutter clean

echo Getting dependencies...
call flutter pub get

if %ERRORLEVEL% NEQ 0 (
    echo Failed to get dependencies. Trying without mirror...
    set PUB_HOSTED_URL=
    set FLUTTER_STORAGE_BASE_URL=
    call flutter pub get
)

if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Could not fetch dependencies. Please check your internet connection.
    pause
    exit /b 1
)

echo Generating launcher icons...
call dart run flutter_launcher_icons

echo Building APK...
call flutter build apk --release

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo BUILD SUCCESSFUL!
    echo ========================================
    echo APK Location: build\app\outputs\flutter-apk\MozPN-release-v1.0.0.apk
    echo.
) else (
    echo.
    echo BUILD FAILED!
    echo.
)

pause
