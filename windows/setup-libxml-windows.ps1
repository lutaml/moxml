#Requires -Version 5.1
<#
.SYNOPSIS
    Setup script for building libxml-ruby on Windows

.DESCRIPTION
    This script automates the setup and installation of libxml-ruby on Windows.
    It installs MSYS2 dependencies, sets environment variables, and builds the gem.

.PARAMETER RubyVersion
    The Ruby version being used (e.g., "3.1", "3.2", "3.3")

.PARAMETER Msys2Path
    Path to MSYS2 installation (default: C:\msys64)

.PARAMETER SkipMsys2Install
    Skip MSYS2 package installation (if already done)

.EXAMPLE
    .\setup-libxml-windows.ps1 -RubyVersion "3.3"

.EXAMPLE
    .\setup-libxml-windows.ps1 -RubyVersion "3.1" -Msys2Path "D:\msys64"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$RubyVersion = "3.3",

    [Parameter(Mandatory=$false)]
    [string]$Msys2Path = "C:\msys64",

    [Parameter(Mandatory=$false)]
    [switch]$SkipMsys2Install
)

# Error handling
$ErrorActionPreference = "Stop"

function Write-Header {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Test-Command {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# Determine MSYS2 environment based on Ruby version
function Get-Msys2Environment {
    param([string]$Version)

    $major = [int]($Version.Split('.')[0])
    $minor = [int]($Version.Split('.')[1])

    if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 1)) {
        return @{
            Name = "ucrt64"
            PackagePrefix = "mingw-w64-ucrt-x86_64"
            Path = "$Msys2Path\ucrt64"
        }
    } else {
        return @{
            Name = "mingw64"
            PackagePrefix = "mingw-w64-x86_64"
            Path = "$Msys2Path\mingw64"
        }
    }
}

Write-Header "libxml-ruby Windows Setup Script"

# Check prerequisites
Write-Host "Checking prerequisites..."

if (-not (Test-Command "ruby")) {
    Write-Error "Ruby is not installed or not in PATH"
    Write-Host "Please install Ruby from https://rubyinstaller.org/"
    exit 1
}

$rubyVer = ruby -v
Write-Success "Found Ruby: $rubyVer"

if (-not (Test-Command "gem")) {
    Write-Error "Gem command not found"
    exit 1
}

if (-not (Test-Path $Msys2Path)) {
    Write-Error "MSYS2 not found at $Msys2Path"
    Write-Host "Please install MSYS2 or specify the correct path with -Msys2Path"
    exit 1
}

Write-Success "Found MSYS2 at $Msys2Path"

# Determine environment
$envInfo = Get-Msys2Environment -Version $RubyVersion
Write-Host "Using MSYS2 environment: $($envInfo.Name)"
Write-Host "Package prefix: $($envInfo.PackagePrefix)"

# Install MSYS2 packages
if (-not $SkipMsys2Install) {
    Write-Header "Installing MSYS2 Packages"

    $packages = @(
        "$($envInfo.PackagePrefix)-libxml2"
        "$($envInfo.PackagePrefix)-libiconv"
        "$($envInfo.PackagePrefix)-zlib"
        "$($envInfo.PackagePrefix)-gcc"
        "$($envInfo.PackagePrefix)-make"
    )

    foreach ($package in $packages) {
        Write-Host "Installing $package..."
        & "$Msys2Path\usr\bin\pacman.exe" -S --needed --noconfirm $package
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Installed $package"
        } else {
            Write-Error "Failed to install $package"
        }
    }
} else {
    Write-Host "Skipping MSYS2 package installation (--SkipMsys2Install specified)"
}

# Set environment variables
Write-Header "Setting Environment Variables"

$env:WINDOWS_XML2_INCLUDE = "$($envInfo.Path)\include\libxml2"
$env:WINDOWS_XML2_LIB = "$($envInfo.Path)\lib"

# Add to system environment variables (requires admin)
$setSystemEnv = Read-Host "Set environment variables system-wide? (requires admin) [y/N]"
if ($setSystemEnv -eq 'y' -or $setSystemEnv -eq 'Y') {
    try {
        [Environment]::SetEnvironmentVariable("WINDOWS_XML2_INCLUDE", $env:WINDOWS_XML2_INCLUDE, "Machine")
        [Environment]::SetEnvironmentVariable("WINDOWS_XML2_LIB", $env:WINDOWS_XML2_LIB, "Machine")

        # Add to PATH if not already there
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        $binPath = "$($envInfo.Path)\bin"
        if (-not $currentPath.Contains($binPath)) {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$binPath", "Machine")
        }
        Write-Success "Environment variables set system-wide"
    } catch {
        Write-Error "Failed to set system environment variables (run as Administrator)"
        Write-Host "You can set them manually:"
        Write-Host "  WINDOWS_XML2_INCLUDE = $($env:WINDOWS_XML2_INCLUDE)"
        Write-Host "  WINDOWS_XML2_LIB = $($env:WINDOWS_XML2_LIB)"
    }
}

# Verify installation
Write-Header "Verifying Installation"

$includePath = $env:WINDOWS_XML2_INCLUDE
if (Test-Path $includePath) {
    Write-Success "Include path exists: $includePath"

    # Check for key header files
    $requiredHeaders = @("libxml/parser.h", "libxml/tree.h", "libxml/xmlversion.h")
    foreach ($header in $requiredHeaders) {
        $headerPath = Join-Path $includePath $header
        if (Test-Path $headerPath) {
            Write-Success "Found $header"
        } else {
            Write-Error "Missing $header"
        }
    }
} else {
    Write-Error "Include path not found: $includePath"
}

$libPath = $env:WINDOWS_XML2_LIB
if (Test-Path $libPath) {
    Write-Success "Library path exists: $libPath"
} else {
    Write-Error "Library path not found: $libPath"
}

# Build options
Write-Header "Build Options"

$buildChoice = Read-Host @"
Choose installation method:
1. Install pre-built gem (easiest, recommended)
2. Build from source
3. Configure Bundler only

Enter choice [1-3]
"@

switch ($buildChoice) {
    "1" {
        Write-Host "Installing pre-built gem..."

        if ($envInfo.Name -eq "ucrt64") {
            gem install libxml-ruby-x64-mingw-ucrt
        } else {
            gem install libxml-ruby-x64-mingw32
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Pre-built gem installed successfully"
        } else {
            Write-Error "Failed to install pre-built gem"
        }
    }

    "2" {
        Write-Host "Building from source..."

        # Clone repository
        $cloneDir = "..\libxml-ruby-src"
        if (-not (Test-Path $cloneDir)) {
            git clone https://github.com/xml4r/libxml-ruby.git $cloneDir
        }

        Push-Location $cloneDir

        # Install dependencies
        bundle install

        # Compile
        rake compile

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Compilation successful"

            # Run tests
            rake test

            # Build gem
            rake build

            # Install
            $gemFile = Get-ChildItem "pkg\libxml-ruby-*.gem" | Select-Object -First 1
            if ($gemFile) {
                gem install $gemFile.FullName
                Write-Success "Gem installed from source"
            }
        } else {
            Write-Error "Compilation failed"
        }

        Pop-Location
    }

    "3" {
        Write-Host "Configuring Bundler..."
        Write-Host "Run the following command in your project directory:"
        Write-Host ""
        Write-Host "  bundle config build.libxml-ruby --with-xml2-include=$includePath --with-xml2-lib=$libPath"
        Write-Host ""
        Write-Host "Then run:"
        Write-Host ""
        Write-Host "  bundle install"
        Write-Host ""
    }

    default {
        Write-Host "Invalid choice. Please run the script again."
    }
}

# Final verification
Write-Header "Final Verification"

$testScript = @"
require 'libxml'
puts "libxml-ruby version: #{LibXML::XML::VERSION}"
puts "libxml2 version: #{LibXML::XML::LIBXML_VERSION}"
doc = LibXML::XML::Document.string('<root><child/></root>')
puts "Test parse successful: #{doc.root.name == 'root'}"
"@

try {
    $result = $testScript | ruby 2>&1
    Write-Success "libxml-ruby is working correctly"
    Write-Host $result
} catch {
    Write-Error "Verification failed"
    Write-Host $result
}

Write-Header "Setup Complete"
Write-Host @"

Next steps:
1. If you installed the pre-built gem or built from source, you're ready to use libxml-ruby
2. If you chose Bundler configuration, run the bundle commands shown above
3. Copy DLLs from $($envInfo.Path)\bin to your Ruby bin directory or project dlls/ folder:
   - libxml2-2.dll
   - libiconv-2.dll
   - zlib1.dll

For troubleshooting, see BUILD_LIBXML_WINDOWS.md
"@
