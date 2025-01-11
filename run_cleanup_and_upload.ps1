# PowerShell script to run cleanup and upload process
param (
    [switch]$Force,
    [string]$WorkingDir = $PSScriptRoot
)

# Function to write colored output
function Write-Status {
    param(
        [string]$Message,
        [string]$Status = "INFO",
        [string]$Color = "White"
    )
    Write-Host "[$Status] $Message" -ForegroundColor $Color
}

# Function to check R installation
function Test-RInstallation {
    try {
        $rVersion = (R --version)[0]
        Write-Status "Found R: $rVersion" "OK" "Green"
        return $true
    }
    catch {
        Write-Status "R is not installed or not in PATH" "ERROR" "Red"
        return $false
    }
}

# Function to install R packages
function Install-RPackages {
    $packages = @(
        "rmarkdown",
        "knitr",
        "xml2",
        "stringr",
        "dotenv",
        "httr",
        "jsonlite",
        "base64enc",
        "networkD3",
        "dplyr",
        "plotly",
        "htmlwidgets",
        "DiagrammeR",
        "DiagrammeRsvg",
        "rsvg",
        "webshot",
        "htmltools",
        "svglite"
    )

    $installScript = $packages | ForEach-Object {
        "if (!require('$_', quietly = TRUE)) install.packages('$_', repos='https://cloud.r-project.org')"
    }
    
    $installCommand = $installScript -join "; "
    Write-Status "Installing required R packages..." "SETUP" "Yellow"
    R --quiet -e $installCommand
}

# Function to check and create required files
function Initialize-Environment {
    # Check for .env file
    if (-not (Test-Path ".env")) {
        Write-Status "Creating .env file from template" "SETUP" "Yellow"
        Copy-Item ".env.example" ".env" -ErrorAction SilentlyContinue
    }

    # Create recovery log if it doesn't exist
    if (-not (Test-Path "recovery_log.md")) {
        @"
# Recovery Log
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Process History

"@ | Out-File "recovery_log.md" -Encoding utf8
    }
}

# Main execution
try {
    Set-Location $WorkingDir
    Write-Status "Starting cleanup and upload process" "START" "Cyan"

    # Check R installation
    if (-not (Test-RInstallation)) {
        throw "R is required but not found"
    }

    # Initialize environment
    Initialize-Environment

    # Install required R packages
    Install-RPackages

    # Run the cleanup and upload process
    Write-Status "Running cleanup and upload scripts..." "PROCESS" "Yellow"
    R --quiet -e "source('cleanup.R')"

    # Check if gallery.md was created
    if (Test-Path "gallery.md") {
        Write-Status "Gallery created successfully" "SUCCESS" "Green"
        Get-Content "gallery.md" | Select-Object -First 5 | ForEach-Object {
            Write-Host "    $_" -ForegroundColor Gray
        }
        Write-Host "    ..." -ForegroundColor Gray
    }
    else {
        Write-Status "Gallery creation may have failed" "WARNING" "Yellow"
    }

    # Check output file size
    if (Test-Path "agentic_context_analysis.html") {
        $size = (Get-Item "agentic_context_analysis.html").Length / 1MB
        Write-Status "Output file size: $($size.ToString('0.00')) MB" "INFO" "White"
    }

    Write-Status "Process completed successfully" "SUCCESS" "Green"
}
catch {
    Write-Status "Error: $_" "ERROR" "Red"
    Write-Status "Stack trace: $($_.ScriptStackTrace)" "ERROR" "Red"
    exit 1
}
finally {
    # Append completion status to recovery log
    $status = if ($?) { "SUCCESS" } else { "FAILED" }
    Add-Content "recovery_log.md" "- [$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] Process completed with status: $status"
} 