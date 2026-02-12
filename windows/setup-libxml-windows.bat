@echo off
REM Setup script for building libxml-ruby on Windows
REM This batch file provides a simpler alternative to the PowerShell script

echo ========================================
echo libxml-ruby Windows Setup
echo ========================================
echo.

REM Check for Ruby
ruby -v >nul 2>&1
if errorlevel 1 (
    echo ERROR: Ruby is not installed or not in PATH
    echo Please install Ruby from https://rubyinstaller.org/
    exit /b 1
)

echo Found Ruby:
ruby -v
echo.

REM Detect Ruby platform and set appropriate environment
for /f "tokens=*" %%a in ('ruby -e "puts RUBY_PLATFORM"') do set RUBY_PLATFORM=%%a
echo Ruby platform: %RUBY_PLATFORM%

if "%RUBY_PLATFORM%"=="x64-mingw-ucrt" (
    echo Detected UCRT64 environment (Ruby 3.1+)
    set MSYS2_ENV=ucrt64
    set PKG_PREFIX=mingw-w64-ucrt-x86_64
    set MSYS2_LIB_PATH=C:\msys64\ucrt64
) else if "%RUBY_PLATFORM%"=="x64-mingw32" (
    echo Detected MinGW64 environment
    set MSYS2_ENV=mingw64
    set PKG_PREFIX=mingw-w64-x86_64
    set MSYS2_LIB_PATH=C:\msys64\mingw64
) else if "%RUBY_PLATFORM%"=="i386-mingw32" (
    echo Detected MinGW32 environment
    set MSYS2_ENV=mingw32
    set PKG_PREFIX=mingw-w64-i686
    set MSYS2_LIB_PATH=C:\msys64\mingw32
) else (
    echo Unknown platform: %RUBY_PLATFORM%
    echo Assuming UCRT64 (Ruby 3.1+)
    set MSYS2_ENV=ucrt64
    set PKG_PREFIX=mingw-w64-ucrt-x86_64
    set MSYS2_LIB_PATH=C:\msys64\ucrt64
)

echo.
echo MSYS2 Environment: %MSYS2_ENV%
echo Package Prefix: %PKG_PREFIX%
echo.

REM Check MSYS2 installation
if not exist C:\msys64 (
    echo ERROR: MSYS2 not found at C:\msys64
    echo Please install MSYS2 or modify this script with the correct path
    exit /b 1
)

echo Found MSYS2 at C:\msys64
echo.

REM Set environment variables
set WINDOWS_XML2_INCLUDE=%MSYS2_LIB_PATH%\include\libxml2
set WINDOWS_XML2_LIB=%MSYS2_LIB_PATH%\lib

echo Environment variables set:
echo   WINDOWS_XML2_INCLUDE=%WINDOWS_XML2_INCLUDE%
echo   WINDOWS_XML2_LIB=%WINDOWS_XML2_LIB%
echo.

REM Menu
echo Choose installation method:
echo   1. Install pre-built gem (easiest, recommended)
echo   2. Install MSYS2 dependencies only
echo   3. Set environment variables only
echo   4. Verify installation
echo   5. Show help
echo.

set /p choice="Enter choice [1-5]: "

if "%choice%"=="1" goto install_prebuilt
if "%choice%"=="2" goto install_deps
if "%choice%"=="3" goto set_env
if "%choice%"=="4" goto verify
if "%choice%"=="5" goto help

echo Invalid choice
goto end

:install_prebuilt
echo.
echo Installing pre-built gem...

if "%MSYS2_ENV%"=="ucrt64" (
    gem install libxml-ruby-x64-mingw-ucrt
) else (
    gem install libxml-ruby-x64-mingw32
)

if errorlevel 1 (
    echo.
    echo ERROR: Installation failed
    echo Try building from source or check your Ruby version
) else (
    echo.
    echo SUCCESS: Pre-built gem installed
    echo.
    echo Don't forget to copy DLLs from %MSYS2_LIB_PATH%\bin to your Ruby bin directory:
    echo   - libxml2-2.dll
    echo   - libiconv-2.dll
    echo   - zlib1.dll
)
goto end

:install_deps
echo.
echo Installing MSYS2 dependencies...
echo This may take several minutes...
echo.

C:\msys64\usr\bin\pacman.exe -S --needed --noconfirm %PKG_PREFIX%-libxml2
C:\msys64\usr\bin\pacman.exe -S --needed --noconfirm %PKG_PREFIX%-libiconv
C:\msys64\usr\bin\pacman.exe -S --needed --noconfirm %PKG_PREFIX%-zlib
C:\msys64\usr\bin\pacman.exe -S --needed --noconfirm %PKG_PREFIX%-gcc
C:\msys64\usr\bin\pacman.exe -S --needed --noconfirm %PKG_PREFIX%-make

echo.
echo Dependencies installed
echo.
echo NOTE: This script did not set permanent environment variables.
echo Run option 3 or set them manually in System Properties.
goto end

:set_env
echo.
echo Setting environment variables...
echo.
echo Current session:
echo   WINDOWS_XML2_INCLUDE=%WINDOWS_XML2_INCLUDE%
echo   WINDOWS_XML2_LIB=%WINDOWS_XML2_LIB%
echo.
echo To set these permanently, run these commands as Administrator:
echo.
echo   setx WINDOWS_XML2_INCLUDE "%WINDOWS_XML2_INCLUDE%" /M
echo   setx WINDOWS_XML2_LIB "%WINDOWS_XML2_LIB%" /M
echo.
echo Or use Windows System Properties -
echo Advanced -
e Environment Variables
goto end

:verify
echo.
echo Verifying installation...
echo.

echo Checking include path:
if exist "%WINDOWS_XML2_INCLUDE%\libxml\parser.h" (
    echo   [OK] libxml/parser.h found
) else (
    echo   [MISSING] libxml/parser.h not found
)

if exist "%WINDOWS_XML2_INCLUDE%\libxml\tree.h" (
    echo   [OK] libxml/tree.h found
) else (
    echo   [MISSING] libxml/tree.h not found
)

echo.
echo Checking library path:
if exist "%WINDOWS_XML2_LIB%" (
    echo   [OK] Library path exists
) else (
    echo   [MISSING] Library path not found
)

echo.
echo Testing libxml-ruby:
ruby -e "require 'libxml'; puts 'libxml-ruby version: ' + LibXML::XML::VERSION" 2>nul
if errorlevel 1 (
    echo   [NOT INSTALLED] libxml-ruby gem not found
    echo   Install it first using option 1
) else (
    echo   [OK] libxml-ruby is installed
)

goto end

:help
echo.
echo BUILD_LIBXML_WINDOWS.bat - Setup libxml-ruby on Windows
echo.
echo This script helps you install libxml-ruby on Windows by:
echo   - Detecting your Ruby platform (UCRT64 or MinGW)
echo   - Installing MSYS2 dependencies (libxml2, libiconv, zlib)
echo   - Setting required environment variables
echo   - Installing the pre-built gem
echo.
echo PREREQUISITES:
echo   - Ruby 3.0+ with DevKit installed from rubyinstaller.org
echo   - MSYS2 (included with Ruby+Devkit)
echo   - Internet connection for downloading packages
echo.
echo OPTIONS:
echo   1. Install pre-built gem - Quickest method, downloads pre-compiled gem
echo   2. Install MSYS2 deps    - Only installs required MSYS2 packages
echo   3. Set environment vars  - Shows how to set permanent env vars
echo   4. Verify installation   - Checks if everything is set up correctly
echo   5. Show this help        - Displays this help message
echo.
echo TROUBLESHOOTING:
echo   - If installation fails, ensure MSYS2 is in your PATH
echo   - Run 'ridk install' after installing Ruby if MSYS2 is not configured
echo   - Check BUILD_LIBXML_WINDOWS.md for detailed instructions
echo.
echo DLL FILES:
echo After installation, copy these DLLs from %MSYS2_LIB_PATH%\bin to your Ruby bin:
echo   - libxml2-2.dll
echo   - libiconv-2.dll
echo   - zlib1.dll
echo.
echo Or use the DLLs already provided in the dlls/ folder of this project.
goto end

:end
echo.
echo ========================================
echo Setup complete
echo ========================================
pause
