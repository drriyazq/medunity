@echo off
REM Generate the MedUnity upload keystore and the matching key.properties file.
REM Run this ONCE on your Windows machine, store the .jks file safely.
REM
REM Usage: from the android\ folder, double-click make-keystore.bat
REM
REM IMPORTANT: back up the generated .jks to a second location (cloud + USB).
REM            If you lose it, you cannot update the app on Play Store ever.

setlocal

echo =========================================================
echo   MedUnity Upload Keystore Generator
echo =========================================================
echo.

set "KEYSTORE_PATH=%USERPROFILE%\medunity-upload.jks"
set "ALIAS=medunity-upload"

if exist "%KEYSTORE_PATH%" (
    echo A keystore already exists at: %KEYSTORE_PATH%
    echo Refusing to overwrite. If you really want a new one, delete the
    echo existing file manually first ^(but make VERY sure you do not need it^).
    pause
    exit /b 1
)

echo The keystore will be created at: %KEYSTORE_PATH%
echo Alias: %ALIAS%
echo.
echo You will be prompted for:
echo   - Keystore password ^(remember this!^)
echo   - Your name, org, city etc. ^(any reasonable values^)
echo.
pause

keytool -genkey -v ^
    -keystore "%KEYSTORE_PATH%" ^
    -storetype JKS ^
    -keyalg RSA ^
    -keysize 2048 ^
    -validity 10000 ^
    -alias %ALIAS%

if errorlevel 1 (
    echo.
    echo keytool failed. Is Java installed and on PATH?
    pause
    exit /b 1
)

echo.
echo =========================================================
echo   Keystore created successfully.
echo =========================================================
echo.
echo Next step: create android\key.properties with:
echo.
echo   storeFile=%KEYSTORE_PATH:\=/%
echo   storePassword=^<the password you just set^>
echo   keyAlias=%ALIAS%
echo   keyPassword=^<the key password you just set^>
echo.
echo See android\key.properties.template for the exact format.
echo.
echo BACK UP THE FILE: %KEYSTORE_PATH%
echo If you lose this file, Play Store will NEVER accept an update again.
echo.
pause
