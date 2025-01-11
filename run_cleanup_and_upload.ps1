# PowerShell script to run cleanup and upload process
param (
    [switch]$Force,
    [string]$WorkingDir = $PSScriptRoot,
    [string]$RPath = "D:\Utils\R\R-4.4.0\bin",
    [switch]$TestMode,
    [string]$LogLevel = "INFO"
)

# Enhanced logging with timestamps and levels
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "MAIN"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "INFO" { "White" }
        "DEBUG" { "Gray" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    
    $logMessage = "[$timestamp][$Level][$Component] $Message"
    Write-Host $logMessage -ForegroundColor $color
    
    # Append to log file
    $logMessage | Out-File -FilePath "process.log" -Append
}

# Function to validate environment variables
function Test-Environment {
    Write-Log "Validating environment configuration..." "INFO" "ENV"
    
    # Load .env file if it exists
    if (Test-Path ".env") {
        Get-Content ".env" | ForEach-Object {
            if ($_ -match '^([^#][^=]+)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                if ($value) {
                    [Environment]::SetEnvironmentVariable($name, $value)
                    Write-Log "Loaded $name from .env" "DEBUG" "ENV"
                }
            }
        }
    }
    
    $requiredVars = @(
        @{
            Name        = "IMGUR_CLIENT_ID"
            Optional    = $false
            Description = "Imgur API Client ID for image hosting"
        },
        @{
            Name        = "IMGUR_CLIENT_SECRET"
            Optional    = $false
            Description = "Imgur API Client Secret for authentication"
        },
        @{
            Name        = "IMGUR_REFRESH_TOKEN"
            Optional    = $true
            Description = "Imgur Refresh Token for extended access"
        },
        @{
            Name        = "POSTGRES_URL"
            Optional    = $true
            Description = "PostgreSQL connection URL"
        }
    )
    
    $missingRequired = @()
    $warnings = @()
    
    foreach ($var in $requiredVars) {
        $value = [Environment]::GetEnvironmentVariable($var.Name)
        if (-not $value) {
            if (-not $var.Optional) {
                $missingRequired += @{
                    Name        = $var.Name
                    Description = $var.Description
                }
            }
            else {
                $warnings += "Optional variable $($var.Name) not set: $($var.Description)"
            }
        }
        else {
            Write-Log "Found $($var.Name) configuration" "DEBUG" "ENV"
        }
    }
    
    # Report warnings
    foreach ($warning in $warnings) {
        Write-Log $warning "WARN" "ENV"
    }
    
    # Report missing required variables with descriptions
    if ($missingRequired.Count -gt 0) {
        Write-Log "Missing required environment variables:" "ERROR" "ENV"
        foreach ($missing in $missingRequired) {
            Write-Log "  - $($missing.Name): $($missing.Description)" "ERROR" "ENV"
        }
        return $false
    }
    
    # Validate R configuration
    $rLibsUser = [Environment]::GetEnvironmentVariable("R_LIBS_USER")
    if ($rLibsUser) {
        if (-not (Test-Path $rLibsUser)) {
            try {
                New-Item -ItemType Directory -Path $rLibsUser -Force | Out-Null
                Write-Log "Created R library directory: $rLibsUser" "INFO" "ENV"
            }
            catch {
                Write-Log "Failed to create R library directory: $_" "WARN" "ENV"
            }
        }
    }
    
    return $true
}

# Function to test Imgur connection
function Test-ImgurConnection {
    Write-Log "Testing Imgur API connection..." "INFO" "IMGUR"
    
    try {
        $clientId = [Environment]::GetEnvironmentVariable("IMGUR_CLIENT_ID")
        $clientSecret = [Environment]::GetEnvironmentVariable("IMGUR_CLIENT_SECRET")
        
        if (-not $clientId -or -not $clientSecret) {
            throw "Imgur credentials not properly configured"
        }
        
        $headers = @{
            "Authorization" = "Client-ID $clientId"
        }
        
        Write-Log "Attempting to connect to Imgur API..." "DEBUG" "IMGUR"
        $response = Invoke-RestMethod -Uri "https://api.imgur.com/3/credits" -Headers $headers
        
        if ($response.success -eq $false) {
            throw "Imgur API returned error: $($response.data.error)"
        }
        
        Write-Log "Successfully connected to Imgur API" "SUCCESS" "IMGUR"
        Write-Log "API Credits remaining: $($response.data.remaining)" "INFO" "IMGUR"
        Write-Log "UserLimit: $($response.data.UserLimit), ClientLimit: $($response.data.ClientLimit)" "DEBUG" "IMGUR"
        
        return $true
    }
    catch {
        Write-Log "Failed to connect to Imgur: $_" "ERROR" "IMGUR"
        Write-Log "Please verify your Imgur credentials in .env file" "ERROR" "IMGUR"
        Write-Log "Visit https://api.imgur.com/oauth2/addclient to get credentials" "INFO" "IMGUR"
        return $false
    }
}

# Enhanced R environment setup with version check
function Setup-REnvironment {
    Write-Log "Setting up R environment..." "INFO" "R"
    
    # Add R to path if not already there
    $env:Path = "$RPath;$env:Path"
    
    # Set R_HOME environment variable
    $env:R_HOME = (Split-Path $RPath -Parent)
    Write-Log "Set R_HOME to: $env:R_HOME" "DEBUG" "R"
    
    # Verify R installation and version
    try {
        $rExe = Join-Path $RPath "R.exe"
        if (-not (Test-Path $rExe)) {
            throw "R.exe not found at: $rExe"
        }
        $rVersion = & $rExe --version 2>&1
        $minVersion = [Version]"4.0.0"
        $currentVersion = [Version]($rVersion[0] -replace 'R version ([0-9.]+).*', '$1')
        
        if ($currentVersion -lt $minVersion) {
            Write-Log "R version $currentVersion is below minimum required version $minVersion" "ERROR" "R"
            return $false
        }
        
        Write-Log "Found R version $currentVersion" "SUCCESS" "R"
        return $true
    }
    catch {
        Write-Log "Error verifying R installation: $_" "ERROR" "R"
        return $false
    }
}

# Function to run tests
function Invoke-Tests {
    Write-Log "Running test suite..." "INFO" "TEST"
    
    $tests = @(
        @{
            Name = "Environment Variables"
            Test = { Test-Environment }
        },
        @{
            Name = "R Installation"
            Test = { Setup-REnvironment }
        },
        @{
            Name = "Imgur Connectivity"
            Test = { Test-ImgurConnection }
        },
        @{
            Name = "File Permissions"
            Test = {
                Test-Path -Path $WorkingDir -PathType Container -IsValid
            }
        }
    )
    
    $failedTests = @()
    foreach ($test in $tests) {
        Write-Log "Running test: $($test.Name)" "INFO" "TEST"
        $result = & $test.Test
        if (-not $result) {
            $failedTests += $test.Name
            Write-Log "Test failed: $($test.Name)" "ERROR" "TEST"
        }
        else {
            Write-Log "Test passed: $($test.Name)" "SUCCESS" "TEST"
        }
    }
    
    if ($failedTests.Count -gt 0) {
        Write-Log "Failed tests: $($failedTests -join ', ')" "ERROR" "TEST"
        return $false
    }
    
    Write-Log "All tests passed successfully" "SUCCESS" "TEST"
    return $true
}

# Function to get R version safely
function Get-RVersion {
    try {
        $rExe = Join-Path $RPath "R.exe"
        if (Test-Path $rExe) {
            $version = & $rExe --version 2>&1
            return $version[0]
        }
    }
    catch {
        return "Unknown"
    }
    return "Not Found"
}

# Main execution
try {
    Write-Log "Starting cleanup and upload process" "INFO" "MAIN"
    Set-Location $WorkingDir
    
    # Initialize variables
    $size = 0
    $rVersion = "Unknown"
    
    # Run tests first if in test mode
    if ($TestMode) {
        if (-not (Invoke-Tests)) {
            throw "Test suite failed"
        }
    }
    
    # Validate environment
    if (-not (Test-Environment)) {
        throw "Environment validation failed"
    }
    
    # Setup R environment
    if (-not (Setup-REnvironment)) {
        throw "Failed to setup R environment"
    }
    
    # Get R version for logging
    $rVersion = Get-RVersion
    
    # Test Imgur connection
    if (-not (Test-ImgurConnection)) {
        throw "Failed to connect to Imgur"
    }
    
    # Run the cleanup and upload process
    Write-Log "Running cleanup and upload scripts..." "INFO" "PROCESS"
    $rExe = Join-Path $RPath "R.exe"
    & $rExe --quiet -e "source('cleanup.R')"
    
    # Check output files
    if (Test-Path "agentic_context_analysis.html") {
        $size = (Get-Item "agentic_context_analysis.html").Length / 1MB
        Write-Log "Output file size: $($size.ToString('0.00')) MB" "INFO" "OUTPUT"
        
        # Add link to the output
        $outputUrl = "https://somacsf.github.io/cursor-agent-analysis/agentic_context_analysis.html"
        Write-Log "Output available at: $outputUrl" "SUCCESS" "OUTPUT"
    }
    else {
        Write-Log "Output file not found" "WARN" "OUTPUT"
    }
    
    Write-Log "Process completed successfully" "SUCCESS" "MAIN"
}
catch {
    Write-Log "Critical error: $_" "ERROR" "MAIN"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR" "MAIN"
    exit 1
}
finally {
    # Append completion status to recovery log with detailed summary
    $status = if ($?) { "SUCCESS" } else { "FAILED" }
    $summary = @"
## Process Run - $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
- Status: $status
- R Version: $rVersion
- Output Size: $(if ($size -gt 0) { "$($size.ToString('0.00')) MB" } else { "N/A" })
- Log File: process.log
- Output URL: $(if (Test-Path "agentic_context_analysis.html") { "https://somacsf.github.io/cursor-agent-analysis/agentic_context_analysis.html" } else { "Not available" })

"@
    Add-Content "recovery_log.md" $summary
} 