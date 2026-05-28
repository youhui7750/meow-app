@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ===================================================
echo   開始安裝 Firebase 與 FlutterFire 開發環境
echo ===================================================

echo === 1. 清理舊有或損壞的 firebase-tools ===
call npm uninstall -g firebase-tools
call npm cache clean --force
powershell -Command "Remove-Item -Recurse -Force '$env:APPDATA\npm\node_modules\firebase-tools' -ErrorAction SilentlyContinue"

echo === 2. 強制重新安裝最新版 firebase-tools ===
call npm install -g firebase-tools --force

echo === 3. 執行 Firebase 登入 ===
echo 請在瀏覽器中完成登入。登入完成後，請返回此視窗。
call firebase login

echo === 4. 開始全域安裝 flutterfire_cli ===
call dart pub global activate flutterfire_cli

echo === 5. 安全設定環境變數與解鎖 PowerShell 權限 ===
powershell -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"
echo [成功] 已自動解鎖 PowerShell 腳本執行權限。

set "PUB_BIN_PATH=%LOCALAPPDATA%\Pub\Cache\bin"
if "%PUB_BIN_PATH%"=="" set "PUB_BIN_PATH=%USERPROFILE%\AppData\Local\Pub\Cache\bin"

set "NPM_BIN_PATH=%APPDATA%\npm"
if "%NPM_BIN_PATH%"=="" set "NPM_BIN_PATH=%USERPROFILE%\AppData\Roaming\npm"

echo 偵測到的 FlutterFire 路徑: %PUB_BIN_PATH%
echo 偵測到的 Firebase CLI 路徑: %NPM_BIN_PATH%

powershell -Command "$p='%PUB_BIN_PATH%'; $n='%NPM_BIN_PATH%'; $old=[Environment]::GetEnvironmentVariable('Path','User'); $list=$old -split ';' | Where-Object { $_ -ne '' }; if ($list -notcontains $p) { $list += $p }; if ($list -notcontains $n) { $list += $n }; $new=$list -join ';'; [Environment]::SetEnvironmentVariable('Path', $new, 'User');"

echo ===================================================
echo  🎉 所有環境安裝、無損雙變數設定與權限開通已全數完成！
echo  ⚠️ 注意：請「重新開啟」你的全新的 PowerShell 視窗，
echo ===================================================
pause
