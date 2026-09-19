@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
:: UBports Garnet Fastboot Installer
:: ============================================================

set "FASTBOOT=%~dp0bins\fastboot.exe"
set "TMPOUT=%TEMP%\fb_out.txt"
set "FLASHOUT=%TEMP%\fb_flash_out.txt"
set "IMAGE_DIR=%~dp0images"

set "VENDOR_IMG=%IMAGE_DIR%\vendor.img"
set "VENDOR_URL=https://downloads.sourceforge.net/project/ubports-garnet/vendor/vendor-ubports-20260822.img"

set "VENDOR_SHA256=7040abe672844a4e80fba1597951044574334a57a362fdf66f2d879e9a30b9cd"

:: ============================================================
:: Check fastboot
:: ============================================================

if not exist "%FASTBOOT%" (
    echo Error: fastboot.exe not found at:
    echo %FASTBOOT%
    echo.
    echo Make sure bins\fastboot.exe exists next to this script.
    pause
    exit /b 1
)

if not exist "%IMAGE_DIR%" (
    mkdir "%IMAGE_DIR%"
)

:: ============================================================
:: Header
:: ============================================================

echo ==========================================
echo  UBports Garnet Fastboot Installer
echo  For Device: Redmi Note 13 Pro 5G / Poco X6
echo  Codenames: garnetp / garnet / XIG05
echo  Credits: ximiyad123
echo ==========================================
echo.

:: ============================================================
:: Install / Update selection
:: ============================================================

set /p ACTION="Would you like to (I)nstall Ubuntu Touch or (U)pdate Ubuntu Touch? [I/U]: "

if /I "%ACTION%"=="I" (
    set "FRESH_INSTALL=true"
    echo Selected: Install Ubuntu Touch
) else if /I "%ACTION%"=="U" (
    set "FRESH_INSTALL=false"
    echo Selected: Update Ubuntu Touch
) else (
    echo Invalid choice.
    pause
    exit /b 1
)

echo.

:: ============================================================
:: Download vendor if missing
:: ============================================================

if not exist "%VENDOR_IMG%" (
    call :DOWNLOAD_VENDOR

    if errorlevel 1 (
        pause
        exit /b 1
    )
)

:: ============================================================
:: Verify vendor
:: ============================================================

call :VERIFY_VENDOR

if errorlevel 1 (
    pause
    exit /b 1
)

:: ============================================================
:: Check fastboot mode
:: ============================================================

echo Checking fastboot mode...

call :GET_USERSPACE

if /I "!IS_USERSPACE!"=="yes" (
    echo Device is already in fastbootd.
) else (
    echo Device is in bootloader.
    echo Rebooting into fastbootd...

    "%FASTBOOT%" reboot fastboot

    call :WAIT_FOR_FASTBOOT

    call :GET_USERSPACE

    if /I "!IS_USERSPACE!"=="yes" (
        echo Now in fastbootd.
    ) else (
        echo Error: Could not confirm fastbootd mode.
        pause
        exit /b 1
    )
)

echo.

:: ============================================================
:: Device detection
:: ============================================================

echo Checking device codename...

set "DEVICE_PRODUCT="

"%FASTBOOT%" getvar product >"%TMPOUT%" 2>&1

for /f "tokens=2 delims=: " %%A in (
    'findstr /I /C:"product:" "%TMPOUT%"'
) do (
    set "DEVICE_PRODUCT=%%A"
)

if not defined DEVICE_PRODUCT (
    "%FASTBOOT%" getvar partition-type:product >"%TMPOUT%" 2>&1

    for /f "tokens=2 delims=: " %%A in (
        'findstr /I /C:"partition-type:product:" "%TMPOUT%"'
    ) do (
        set "DEVICE_PRODUCT=%%A"
    )
)

set "SUPPORTED=0"

if /I "!DEVICE_PRODUCT!"=="garnetp" set "SUPPORTED=1"
if /I "!DEVICE_PRODUCT!"=="garnet" set "SUPPORTED=1"
if /I "!DEVICE_PRODUCT!"=="XIG05" set "SUPPORTED=1"
if /I "!DEVICE_PRODUCT!"=="xig05" set "SUPPORTED=1"

if "!SUPPORTED!"=="1" (
    echo Detected supported device: !DEVICE_PRODUCT!
) else (
    echo Warning: Unrecognized device codename "!DEVICE_PRODUCT!".
    echo.
    echo This script targets:
    echo   garnetp / garnet / XIG05
    echo   Redmi Note 13 Pro 5G / Poco X6
    echo.

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

:: ============================================================
:: Detect current slot
:: ============================================================

echo Detecting current slot...

set "CURRENT_SLOT="

"%FASTBOOT%" getvar current-slot >"%TMPOUT%" 2>&1

for /f "tokens=2 delims=: " %%A in (
    'findstr /I /C:"current-slot:" "%TMPOUT%"'
) do (
    set "CURRENT_SLOT=%%A"
)

if not defined CURRENT_SLOT (
    echo Error: Unable to detect current slot.
    pause
    exit /b 1
)

if /I "!CURRENT_SLOT!"=="a" (
    set "TARGET_SLOT=b"
) else if /I "!CURRENT_SLOT!"=="b" (
    set "TARGET_SLOT=a"
) else (
    echo Error: Invalid current slot "!CURRENT_SLOT!".
    pause
    exit /b 1
)

set "CURRENT_SUFFIX=_!CURRENT_SLOT!"
set "TARGET_SUFFIX=_!TARGET_SLOT!"

echo Current slot: !CURRENT_SLOT!
echo.

if /I "!FRESH_INSTALL!"=="true" (
    echo Fresh installation will flash BOTH slots.
) else (
    echo Update target slot: !TARGET_SLOT!
)

echo.

:: ============================================================
:: Verify all image checksums
:: ============================================================

echo ==========================================
echo  Checking image files
echo ==========================================
echo.

call :VERIFY_IMAGE "super_empty.img"
if errorlevel 1 exit /b 1

call :VERIFY_IMAGE "odm.img"
if errorlevel 1 exit /b 1

call :VERIFY_IMAGE "system.img"
if errorlevel 1 exit /b 1

call :VERIFY_IMAGE "boot.img"
if errorlevel 1 exit /b 1

if /I "!FRESH_INSTALL!"=="false" (
    call :VERIFY_IMAGE "boot_stock.img"
    if errorlevel 1 exit /b 1
)

if exist "%IMAGE_DIR%\dtbo.img" (
    call :VERIFY_IMAGE "dtbo.img"
    if errorlevel 1 exit /b 1
)

if exist "%IMAGE_DIR%\vendor_boot.img" (
    call :VERIFY_IMAGE "vendor_boot.img"
    if errorlevel 1 exit /b 1
)

if exist "%IMAGE_DIR%\vendor_dlkm.img" (
    call :VERIFY_IMAGE "vendor_dlkm.img"
    if errorlevel 1 exit /b 1
)

echo All image checks completed.
echo.

:: ============================================================
:: FRESH INSTALL
:: ============================================================

if /I "!FRESH_INSTALL!"=="true" goto FRESH_INSTALL

:: ============================================================
:: UPDATE
:: ============================================================

echo ==========================================
echo  Ubuntu Touch Update
echo ==========================================
echo.

echo Current slot: !CURRENT_SLOT!
echo Target slot:  !TARGET_SLOT!
echo.

echo The current slot's logical partitions
echo will NOT be deleted.
echo.

echo Only the target slot will be modified.
echo.

echo Update sequence:
echo.
echo   1. Flash stock boot to boot_!CURRENT_SLOT!
echo   2. Reboot into recovery
echo   3. Enter fastbootd
echo   4. Remove target-slot logical partitions
echo   5. Flash Ubuntu Touch to target slot
echo   6. Flash UT boot to target slot
echo   7. Activate target slot
echo   8. Reboot
echo.

set /p UPDATECHOICE="Continue with update? (Y/N): "

if /I not "!UPDATECHOICE!"=="Y" (
    echo Aborting.
    pause
    exit /b 1
)

echo.

:: ------------------------------------------------------------
:: Step 1
:: Temporary stock boot goes to CURRENT slot
:: ------------------------------------------------------------

echo ==========================================
echo  Step 1: Temporary stock boot
echo ==========================================
echo.

echo Flashing boot_stock.img to:
echo   boot_!CURRENT_SLOT!
echo.

"%FASTBOOT%" flash "boot_!CURRENT_SLOT!" "%IMAGE_DIR%\boot_stock.img"

if errorlevel 1 (
    echo Failed to flash temporary stock boot.
    pause
    exit /b 1
)

echo.

:: ------------------------------------------------------------
:: Step 2
:: Do NOT change active slot yet.
:: Recovery is entered with current slot active.
:: ------------------------------------------------------------

echo ==========================================
echo  Step 2: Rebooting into recovery
echo ==========================================
echo.

echo Rebooting into recovery...

"%FASTBOOT%" reboot recovery

if errorlevel 1 (
    echo Failed to reboot into recovery.
    pause
    exit /b 1
)

call :WAIT_FOR_FASTBOOT

echo.

:: ------------------------------------------------------------
:: Step 3
:: Ensure fastbootd
:: ------------------------------------------------------------

echo ==========================================
echo  Step 3: Entering fastbootd
echo ==========================================
echo.

call :ENSURE_FASTBOOTD

if errorlevel 1 (
    pause
    exit /b 1
)

echo.

:: ------------------------------------------------------------
:: Step 4
:: Delete ONLY target-slot logical partitions
:: ------------------------------------------------------------

echo ==========================================
echo  Step 4: Preparing target slot
echo ==========================================
echo.

echo Current slot:
echo   !CURRENT_SLOT!
echo.

echo Target slot:
echo   !TARGET_SLOT!
echo.

echo Keeping:
echo   system_!CURRENT_SLOT!
echo   vendor_!CURRENT_SLOT!
echo   odm_!CURRENT_SLOT!
echo.

echo Removing target logical partitions:

echo.
echo   system_!TARGET_SLOT!
"%FASTBOOT%" delete-logical-partition "system_!TARGET_SLOT!"

echo.
echo   vendor_!TARGET_SLOT!
"%FASTBOOT%" delete-logical-partition "vendor_!TARGET_SLOT!"

echo.
echo   odm_!TARGET_SLOT!
"%FASTBOOT%" delete-logical-partition "odm_!TARGET_SLOT!"

echo.

:: ------------------------------------------------------------
:: Step 5
:: Flash target slot
:: ------------------------------------------------------------

echo ==========================================
echo  Step 5: Flashing Ubuntu Touch
echo ==========================================
echo.

call :FLASH_IMAGE "dtbo" "dtbo.img" "!TARGET_SUFFIX!" "false"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "odm" "odm.img" "!TARGET_SUFFIX!" "true"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "vendor_boot" "vendor_boot.img" "!TARGET_SUFFIX!" "false"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "vendor_dlkm" "vendor_dlkm.img" "!TARGET_SUFFIX!" "false"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "vendor" "vendor.img" "!TARGET_SUFFIX!" "true"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "system" "system.img" "!TARGET_SUFFIX!" "true"
if errorlevel 1 exit /b 1

:: ------------------------------------------------------------
:: Step 6
:: Replace stock boot with UT boot
:: ------------------------------------------------------------

echo ==========================================
echo  Step 6: Installing UT boot
echo ==========================================
echo.

call :FLASH_IMAGE "boot" "boot.img" "!TARGET_SUFFIX!" "true"
if errorlevel 1 exit /b 1

:: ------------------------------------------------------------
:: Step 7
:: Activate target
:: ------------------------------------------------------------

echo ==========================================
echo  Step 7: Activating target slot
echo ==========================================
echo.

echo Setting active slot to !TARGET_SLOT!...

"%FASTBOOT%" set_active "!TARGET_SLOT!"

if errorlevel 1 (
    echo Failed to activate target slot.
    pause
    exit /b 1
)

echo.

echo ==========================================
echo  Update completed successfully
echo ==========================================
echo.

echo Old slot:
echo   !CURRENT_SLOT!
echo.

echo Updated slot:
echo   !TARGET_SLOT!
echo.

goto FINISH


:: ============================================================
:: FRESH INSTALL
:: ============================================================

:FRESH_INSTALL

echo ==========================================
echo  Fresh Ubuntu Touch Installation
echo ==========================================
echo.

echo This will recreate the dynamic partition
echo layout using super_empty.img.
echo.

set /p SUPERCHOICE="Continue? (Y/N): "

if /I not "!SUPERCHOICE!"=="Y" (
    echo Aborting.
    pause
    exit /b 1
)

echo.

:: ------------------------------------------------------------
:: Wipe super
:: ------------------------------------------------------------

echo ==========================================
echo  Wiping super
echo ==========================================
echo.

"%FASTBOOT%" wipe-super "%IMAGE_DIR%\super_empty.img"

if errorlevel 1 (
    echo ERROR: wipe-super failed.
    pause
    exit /b 1
)

echo super wiped successfully.
echo.

:: ------------------------------------------------------------
:: Userdata wipe
:: ------------------------------------------------------------

echo WARNING: This will erase all user data.
echo.

set /p WIPECHOICE="Wipe userdata now? (Y/N): "

if /I "!WIPECHOICE!"=="Y" (

    echo.
    echo Rebooting to bootloader...

    "%FASTBOOT%" reboot bootloader

    call :WAIT_FOR_FASTBOOT

    echo Wiping userdata and metadata...

    "%FASTBOOT%" -w

    if errorlevel 1 (
        echo fastboot -w failed.
        pause
        exit /b 1
    )

    echo.
    echo Rebooting back into fastbootd...

    "%FASTBOOT%" reboot fastboot

    call :WAIT_FOR_FASTBOOT

    call :ENSURE_FASTBOOTD

    if errorlevel 1 (
        pause
        exit /b 1
    )

    echo.

) else (
    echo Skipping data wipe.
    echo.
)

:: ------------------------------------------------------------
:: Slot A
:: ------------------------------------------------------------

echo ==========================================
echo  Flashing slot A
echo ==========================================
echo.

call :FLASH_IMAGE "dtbo" "dtbo.img" "_a" "false"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "boot" "boot.img" "_a" "true"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "odm" "odm.img" "_a" "true"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "vendor_boot" "vendor_boot.img" "_a" "false"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "vendor_dlkm" "vendor_dlkm.img" "_a" "false"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "vendor" "vendor.img" "_a" "true"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "system" "system.img" "_a" "true"
if errorlevel 1 exit /b 1

:: ------------------------------------------------------------
:: Slot B
:: ------------------------------------------------------------

echo ==========================================
echo  Flashing slot B
echo ==========================================
echo.

call :FLASH_IMAGE "dtbo" "dtbo.img" "_b" "false"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "boot" "boot.img" "_b" "true"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "odm" "odm.img" "_b" "true"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "vendor_boot" "vendor_boot.img" "_b" "false"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "vendor_dlkm" "vendor_dlkm.img" "_b" "false"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "vendor" "vendor.img" "_b" "true"
if errorlevel 1 exit /b 1

call :FLASH_IMAGE "system" "system.img" "_b" "true"
if errorlevel 1 exit /b 1

echo.
echo ==========================================
echo  Both slots have been installed
echo ==========================================
echo.

echo Keeping previously active slot:
echo   !CURRENT_SLOT!

"%FASTBOOT%" set_active "!CURRENT_SLOT!"

if errorlevel 1 (
    echo Warning: Could not restore previous active slot.
)

goto FINISH


:: ============================================================
:: DOWNLOAD VENDOR
:: ============================================================

:DOWNLOAD_VENDOR

echo Downloading vendor image to:
echo   %VENDOR_IMG%
echo.

where curl >nul 2>&1

if !errorlevel! equ 0 (

    curl -L --fail -o "%VENDOR_IMG%" "%VENDOR_URL%"

) else (

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('%VENDOR_URL%', '%VENDOR_IMG%')"

)

if not exist "%VENDOR_IMG%" (
    echo Error: Failed to download vendor.img.
    exit /b 1
)

for %%A in ("%VENDOR_IMG%") do (
    if %%~zA LEQ 0 (
        echo Error: Downloaded vendor.img is empty.
        exit /b 1
    )
)

echo.
echo Download complete.
echo.

exit /b 0


:: ============================================================
:: VERIFY VENDOR
:: ============================================================

:VERIFY_VENDOR

:VERIFY_VENDOR_LOOP

echo Verifying vendor.img SHA-256...
echo.

set "ACTUAL_SHA="

for /f "skip=1 tokens=1" %%A in (
    'certutil -hashfile "%VENDOR_IMG%" SHA256'
) do (
    if not defined ACTUAL_SHA set "ACTUAL_SHA=%%A"
)

if /I "!ACTUAL_SHA!"=="%VENDOR_SHA256%" (
    echo Vendor SHA-256 OK.
    echo.
    exit /b 0
)

echo.
echo ==========================================
echo  WARNING: vendor.img SHA-256 mismatch
echo ==========================================
echo.

echo Expected:
echo   %VENDOR_SHA256%
echo.

echo Actual:
echo   !ACTUAL_SHA!
echo.

echo What would you like to do?
echo.
echo   (R)edownload vendor.img
echo   (F)lash it anyway
echo   (C)ancel
echo.

set /p VENDOR_CHOICE="Choose [R/F/C]: "

if /I "!VENDOR_CHOICE!"=="R" (
    echo.
    call :DOWNLOAD_VENDOR

    if errorlevel 1 (
        exit /b 1
    )

    echo.
    goto VERIFY_VENDOR_LOOP
)

if /I "!VENDOR_CHOICE!"=="F" (
    echo.
    echo WARNING: Flashing vendor.img despite SHA-256 mismatch.
    echo.
    exit /b 0
)

if /I "!VENDOR_CHOICE!"=="C" (
    echo.
    echo Cancelled.
    exit /b 1
)

echo.
echo Invalid choice.
echo.
goto VERIFY_VENDOR_LOOP


:: ============================================================
:: VERIFY IMAGE
:: ============================================================

:VERIFY_IMAGE

set "VERIFY_FILE=%~1"
set "VERIFY_PATH=%IMAGE_DIR%\%VERIFY_FILE%"
set "VERIFY_SUM=%IMAGE_DIR%\%VERIFY_FILE:.img=.sha256%"

if not exist "%VERIFY_PATH%" (
    echo Error: Missing image:
    echo   %VERIFY_PATH%
    exit /b 1
)

if not exist "%VERIFY_SUM%" (
    echo Error: Missing checksum:
    echo   %VERIFY_SUM%
    exit /b 1
)

echo Verifying %VERIFY_FILE%...

set "EXPECTED_SHA="
for /f "tokens=1" %%A in ('type "%VERIFY_SUM%"') do (
    if not defined EXPECTED_SHA set "EXPECTED_SHA=%%A"
)

set "ACTUAL_SHA="

for /f "skip=1 tokens=1" %%A in (
    'certutil -hashfile "%VERIFY_PATH%" SHA256'
) do (
    if not defined ACTUAL_SHA set "ACTUAL_SHA=%%A"
)

if /I "!ACTUAL_SHA!"=="!EXPECTED_SHA!" (
    echo SHA-256 OK.
    echo.
    exit /b 0
)

echo.
echo ==========================================
echo  WARNING: SHA-256 mismatch
echo ==========================================
echo.

echo File:
echo   %VERIFY_PATH%
echo.

echo Expected:
echo   !EXPECTED_SHA!
echo.

echo Actual:
echo   !ACTUAL_SHA!
echo.

set /p VERIFY_CHOICE="Continue anyway? (Y/N): "

if /I "!VERIFY_CHOICE!"=="Y" (
    echo.
    echo WARNING: Continuing with an unverified file.
    echo.
    exit /b 0
)

echo Cancelled.
exit /b 1


:: ============================================================
:: GET USERSPACE
:: ============================================================

:GET_USERSPACE

set "IS_USERSPACE="

"%FASTBOOT%" getvar is-userspace >"%TMPOUT%" 2>&1

for /f "tokens=2 delims=: " %%A in (
    'findstr /I /C:"is-userspace:" "%TMPOUT%"'
) do (
    set "IS_USERSPACE=%%A"
)

exit /b 0


:: ============================================================
:: WAIT FOR FASTBOOT
:: ============================================================

:WAIT_FOR_FASTBOOT

echo Waiting for fastboot device...

for /L %%N in (1,1,60) do (

    "%FASTBOOT%" devices >"%TMPOUT%" 2>&1

    findstr /R /C:".*" "%TMPOUT%" | findstr /R /C:"[0-9A-Za-z]" >nul

    if not errorlevel 1 (
        echo Fastboot device detected.
        exit /b 0
    )

    timeout /t 1 /nobreak >nul
)

echo Error: Device did not return to fastboot.
exit /b 1


:: ============================================================
:: ENSURE FASTBOOTD
:: ============================================================

:ENSURE_FASTBOOTD

call :GET_USERSPACE

if /I "!IS_USERSPACE!"=="yes" (
    echo Device is in fastbootd.
    exit /b 0
)

echo Device is in bootloader.
echo Rebooting into fastbootd...

"%FASTBOOT%" reboot fastboot

if errorlevel 1 (
    echo Failed to request fastbootd.
    exit /b 1
)

call :WAIT_FOR_FASTBOOT

if errorlevel 1 exit /b 1

call :GET_USERSPACE

if /I "!IS_USERSPACE!"=="yes" (
    echo Now in fastbootd.
    exit /b 0
)

echo Error: Could not confirm fastbootd mode.
exit /b 1


:: ============================================================
:: Detect size/full partition errors
:: ============================================================

:IS_SIZE_ERROR

set "SIZE_ERROR=0"

findstr /I /R ^
    /C:"partition.*full" ^
    /C:"partition.*too large" ^
    /C:"partition.*size" ^
    /C:"not enough space" ^
    /C:"insufficient space" ^
    /C:"size.*too large" ^
    /C:"image.*too large" ^
    /C:"file.*too large" ^
    /C:"super.*full" ^
    /C:"super.*space" ^
    /C:"logical partition.*space" ^
    /C:"no space left" ^
    "%FLASHOUT%" >nul

if not errorlevel 1 (
    set "SIZE_ERROR=1"
)

exit /b 0


:: ============================================================
:: WIPE SUPER
:: ============================================================

:WIPE_SUPER

echo.
echo ==========================================
echo  Wiping super
echo ==========================================
echo.

"%FASTBOOT%" wipe-super "%IMAGE_DIR%\super_empty.img"

if errorlevel 1 (
    echo ERROR: wipe-super failed.
    exit /b 1
)

echo.
echo super wiped successfully.
echo.

exit /b 0


:: ============================================================
:: FLASH IMAGE
::
:: %1 = partition base name
:: %2 = image
:: %3 = suffix
:: %4 = required (true/false)
:: ============================================================

:FLASH_IMAGE

set "FLASH_BASE=%~1"
set "FLASH_FILE=%~2"
set "FLASH_SUFFIX=%~3"
set "FLASH_REQUIRED=%~4"

set "FLASH_PATH=%IMAGE_DIR%\%FLASH_FILE%"
set "FLASH_PARTITION=%FLASH_BASE%%FLASH_SUFFIX%"

if not exist "%FLASH_PATH%" (

    if /I "%FLASH_REQUIRED%"=="true" (
        echo.
        echo Error: Required image missing:
        echo   %FLASH_PATH%
        exit /b 1
    )

    echo Skipping optional image:
    echo   %FLASH_PATH%
    echo.

    exit /b 0
)

:: ------------------------------------------------------------
:: First flash attempt
:: ------------------------------------------------------------

echo.
echo ------------------------------------------
echo Flashing:
echo   File:      %FLASH_PATH%
echo   Partition: %FLASH_PARTITION%
echo ------------------------------------------
echo.

"%FASTBOOT%" flash "%FLASH_PARTITION%" "%FLASH_PATH%" >"%FLASHOUT%" 2>&1

set "FLASH_RESULT=!ERRORLEVEL!"

type "%FLASHOUT%"

if "!FLASH_RESULT!"=="0" (
    echo.
    exit /b 0
)

:: ------------------------------------------------------------
:: Check whether this looks like a size problem
:: ------------------------------------------------------------

call :IS_SIZE_ERROR

if "!SIZE_ERROR!"=="0" (
    echo.
    echo Failed to flash %FLASH_FILE%.
    echo The error does not appear to be a partition-size problem.
    echo.
    exit /b 1
)

:: ------------------------------------------------------------
:: Ask about wipe-super
:: ------------------------------------------------------------

echo.
echo ==========================================
echo  Possible dynamic-partition size problem
echo ==========================================
echo.

echo Failed to flash %FLASH_FILE%.
echo.
echo If the error is "size too big" or
echo "partition is full", would you like to
echo (W)ipe super or (C)ancel?
echo.

choice /C WC /N /M "[W/C]: "

if errorlevel 2 (
    echo.
    echo Cancelled.
    exit /b 1
)

if errorlevel 1 (

    call :WIPE_SUPER

    if errorlevel 1 (
        exit /b 1
    )

    echo.
    echo Retrying %FLASH_PARTITION%...
    echo.

    "%FASTBOOT%" flash "%FLASH_PARTITION%" "%FLASH_PATH%"

    if errorlevel 1 (
        echo.
        echo Retry failed.
        exit /b 1
    )

    echo.
    echo Retry succeeded.
    exit /b 0
)

exit /b 1


:: ============================================================
:: FINISH
:: ============================================================

:FINISH

echo.
echo ==========================================
echo  Ubuntu Touch installation/update complete
echo ==========================================
echo.
echo Credits: ximiyad123
echo.

set /p CHOICE="Reboot device into Ubuntu Touch now? (Y/N): "

if /I "!CHOICE!"=="Y" (
    echo.
    echo Rebooting...
    "%FASTBOOT%" reboot
) else (
    echo.
    echo Finished.
    echo Reboot manually when ready.
)

pause
exit /b 0
