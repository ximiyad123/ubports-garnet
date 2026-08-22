@echo off 
setlocal enabledelayedexpansion 
 
set "FASTBOOT=%~dp0bins\fastboot.exe"
set "TMPOUT=%TEMP%\fb_out.txt"
set "IMAGE_DIR=%~dp0images"
set "VENDOR_URL=https://downloads.sourceforge.net/project/ubports-garnet/vendor/vendor-ubports-20260822.img"
 
if not exist "%FASTBOOT%" ( 
    echo Error: fastboot.exe not found at %FASTBOOT% 
    echo Make sure bins\fastboot.exe exists next to this script. 
    pause 
    exit /b 1 
) 

if not exist "%IMAGE_DIR%" mkdir "%IMAGE_DIR%"

echo ========================================== 
echo  UBports Garnet Fastboot Installer         
echo  For Device: Redmi Note 13 Pro 5G / Poco X6   
echo  Codenames: garnetp / garnet / XIG05         
echo  Credits: ximiyad123                       
echo ========================================== 
echo. 

:: Download missing vendor image if needed
set "VENDOR_IMG=%IMAGE_DIR%\vendor.img"
if not exist "%VENDOR_IMG%" (
    echo Downloading vendor image to %VENDOR_IMG%...
    where curl >nul 2>&1
    if !errorlevel! equ 0 (
        curl -L -o "%VENDOR_IMG%" "%VENDOR_URL%"
    ) else (
        powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('%VENDOR_URL%', '%VENDOR_IMG%')"
    )
    if not exist "%VENDOR_IMG%" (
        echo Error: Failed to download vendor.img!
        pause
        exit /b 1
    )
    echo Download complete.
    echo.
)

:: Detect bootloader vs fastbootd 
echo Checking fastboot mode... 
set "IS_USERSPACE=" 
"%FASTBOOT%" getvar is-userspace >"%TMPOUT%" 2>&1
for /f "tokens=2 delims=: " %%A in ('findstr /I "is-userspace" "%TMPOUT%"') do (
    set "IS_USERSPACE=%%A" 
) 
 
if /I "!IS_USERSPACE!"=="yes" ( 
    echo Device is in fastbootd. Continuing... 
) else ( 
    echo Device is in bootloader. Rebooting into fastbootd... 
    "%FASTBOOT%" reboot fastboot 
    echo Waiting for device to come back in fastbootd... 
    timeout /t 5 /nobreak >nul 
    set "IS_USERSPACE=" 
    "%FASTBOOT%" getvar is-userspace >"%TMPOUT%" 2>&1
    for /f "tokens=2 delims=: " %%A in ('findstr /I "is-userspace" "%TMPOUT%"') do (
        set "IS_USERSPACE=%%A" 
    ) 
    if /I "!IS_USERSPACE!"=="yes" ( 
        echo Now in fastbootd. Continuing... 
    ) else ( 
        echo Error: Could not confirm fastbootd mode. Aborting. 
        pause 
        exit /b 1 
    ) 
) 
echo. 
 
:: Detect device codename and verify it's a supported target 
echo Checking device codename... 
set "DEVICE_PRODUCT=" 
"%FASTBOOT%" getvar product >"%TMPOUT%" 2>&1
for /f "tokens=2 delims=: " %%A in ('findstr /I "product" "%TMPOUT%"') do (
    set "DEVICE_PRODUCT=%%A" 
) 
 
set "SUPPORTED=0" 
if /I "!DEVICE_PRODUCT!"=="garnetp" set "SUPPORTED=1" 
if /I "!DEVICE_PRODUCT!"=="garnet" set "SUPPORTED=1" 
if /I "!DEVICE_PRODUCT!"=="XIG05" set "SUPPORTED=1" 
 
if "!SUPPORTED!"=="1" ( 
    echo Detected supported device: !DEVICE_PRODUCT! 
) else ( 
    echo Warning: Unrecognized device codename "!DEVICE_PRODUCT!". 
    echo This script targets garnetp / garnet / XIG05 ^(Redmi Note 13 Pro 5G / Poco X6^). 
    set /p FORCECHOICE="Continue anyway? (Y/N): " 
    if /I "!FORCECHOICE!"=="Y" ( 
        echo Continuing at your own risk... 
    ) else ( 
        echo Aborting. 
        pause 
        exit /b 1 
    ) 
) 
echo. 
 
:: Detect active slot suffix (_a or _b) 
set "SLOT_SUFFIX=" 
set "CURRENT_SLOT=" 
"%FASTBOOT%" getvar current-slot >"%TMPOUT%" 2>&1
for /f "tokens=2 delims=: " %%A in ('findstr /I "current-slot" "%TMPOUT%"') do (
    set "CURRENT_SLOT=%%A" 
) 
 
if defined CURRENT_SLOT ( 
    echo Detected active slot: !CURRENT_SLOT! 
    set "SLOT_SUFFIX=_!CURRENT_SLOT!" 
) else ( 
    echo Warning: Unable to detect active slot suffix. Proceeding without slot suffix... 
) 
 
echo. 
echo Freeing product!SLOT_SUFFIX! from super, and erasing vendor!SLOT_SUFFIX!... 
"%FASTBOOT%" delete-logical-partition product!SLOT_SUFFIX! >nul 2>&1 
"%FASTBOOT%" erase vendor!SLOT_SUFFIX! >nul 2>&1 
 
echo. 
echo WARNING: This will erase all user data on the device. 
echo NOTE: If you are updating Ubuntu Touch, proceed to select No.    
set /p WIPECHOICE="Wipe userdata now? (Y/N): " 
if /I "%WIPECHOICE%"=="Y" ( 
    echo Rebooting to bootloader to perform data wipe... 
    "%FASTBOOT%" reboot bootloader 
    timeout /t 5 /nobreak >nul 
 
    echo Wiping userdata and metadata via fastboot -w... 
    "%FASTBOOT%" -w 
 
    echo Rebooting back into fastbootd... 
    "%FASTBOOT%" reboot fastboot 
    timeout /t 5 /nobreak >nul 
) else ( 
    echo Skipping data wipe. 
) 
echo. 

echo Starting flash sequence...

:: Flash dtbo (Optional)
if exist "%IMAGE_DIR%\dtbo.img" (
    echo Flashing dtbo.img to dtbo!SLOT_SUFFIX!...
    "%FASTBOOT%" flash dtbo!SLOT_SUFFIX! "%IMAGE_DIR%\dtbo.img"
) else (
    echo Skipping optional partition dtbo ^(images\dtbo.img not found^)...
)

:: Flash Boot (Required)
if exist "%IMAGE_DIR%\boot.img" ( 
    echo Flashing boot.img to boot!SLOT_SUFFIX!... 
    "%FASTBOOT%" flash boot!SLOT_SUFFIX! "%IMAGE_DIR%\boot.img" 
) else ( 
    echo Error: boot.img not found in images\ directory! 
    pause 
    exit /b 1 
)

:: Flash vendor_boot (Optional)
if exist "%IMAGE_DIR%\vendor_boot.img" (
    echo Flashing vendor_boot.img to vendor_boot!SLOT_SUFFIX!...
    "%FASTBOOT%" flash vendor_boot!SLOT_SUFFIX! "%IMAGE_DIR%\vendor_boot.img"
) else (
    echo Skipping optional partition vendor_boot ^(images\vendor_boot.img not found^)...
)

:: Flash vendor_dlkm (Optional)
if exist "%IMAGE_DIR%\vendor_dlkm.img" (
    echo Flashing vendor_dlkm.img to vendor_dlkm!SLOT_SUFFIX!...
    "%FASTBOOT%" flash vendor_dlkm!SLOT_SUFFIX! "%IMAGE_DIR%\vendor_dlkm.img"
) else (
    echo Skipping optional partition vendor_dlkm ^(images\vendor_dlkm.img not found^)...
)

:: Flash Vendor (Required)
if exist "%IMAGE_DIR%\vendor.img" ( 
    echo Flashing vendor.img to vendor!SLOT_SUFFIX!... 
    "%FASTBOOT%" flash vendor!SLOT_SUFFIX! "%IMAGE_DIR%\vendor.img" 
) else ( 
    echo Error: vendor.img not found in images\ directory! 
    pause 
    exit /b 1 
)

:: Flash System (Required)
if exist "%IMAGE_DIR%\system.img" ( 
    echo Flashing system.img to system!SLOT_SUFFIX!... 
    "%FASTBOOT%" flash system!SLOT_SUFFIX! "%IMAGE_DIR%\system.img" 
) else ( 
    echo Error: system.img not found in images\ directory! 
    pause 
    exit /b 1 
) 

echo. 
echo ========================================== 
echo  Installation Complete!                    
echo  Credits: ximiyad123                        
echo ========================================== 
echo. 
 
set /p CHOICE="Reboot device into Ubuntu Touch now? (Y/N): " 
if /I "%CHOICE%"=="Y" ( 
    "%FASTBOOT%" reboot 
) else ( 
    echo Finished. Reboot manually when ready. 
) 
 
pause
