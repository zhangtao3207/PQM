@echo off
setlocal
cd /d "%~dp0"

set "BOOTGEN=bootgen"
set "PROGRAM_FLASH=program_flash"

where %BOOTGEN% >nul 2>nul
if errorlevel 1 (
    if exist "D:\zt\Xilinx\SDK\2018.3\bin\bootgen.bat" (
        set "BOOTGEN=D:\zt\Xilinx\SDK\2018.3\bin\bootgen.bat"
    ) else (
        echo bootgen not found. Please run this script in the Xilinx 2018.3 command environment,
        echo or modify BOOTGEN path in this file.
        goto :end
    )
)

where %PROGRAM_FLASH% >nul 2>nul
if errorlevel 1 (
    if exist "D:\zt\Xilinx\SDK\2018.3\bin\program_flash.bat" (
        set "PROGRAM_FLASH=D:\zt\Xilinx\SDK\2018.3\bin\program_flash.bat"
    ) else (
        echo program_flash not found. Please run this script in the Xilinx 2018.3 command environment,
        echo or modify PROGRAM_FLASH path in this file.
        goto :end
    )
)

call "%BOOTGEN%" -image bootbin.bif -arch zynq -o BOOT.bin -w on
if errorlevel 1 goto :error

call "%PROGRAM_FLASH%" -f BOOT.bin -offset 0 -flash_type qspi-x4-single -fsbl zynq_fsbl.elf
if errorlevel 1 goto :error

echo.
echo BOOT.bin created and flashed successfully.
goto :end

:error
echo.
echo Build or flash failed. Check the messages above.

:end
pause
