#Requires -Version 5.1
<#
.SYNOPSIS
    Logging module for SCCM lab automation scripts.

.DESCRIPTION
    This module provides consistent, structured logging for all lab automation
    scripts. It outputs to both the console (with colors) and to log files.

    WHY THIS MODULE EXISTS:
    -----------------------
    When automating complex infrastructure deployments, logging is critical for:
    1. Debugging - When something fails, you need to know exactly what happened
    2. Auditing - Track what changes were made and when
    3. Progress tracking - See where the script is in a long process
    4. Documentation - Logs serve as a record of the deployment

    HOW POWERSHELL MODULES WORK:
    ----------------------------
    A PowerShell module (.psm1) is a package of related functions. When you run
    `Import-Module Logger.psm1`, PowerShell loads all the functions defined here
    into your session. The `Export-ModuleMember` command at the bottom controls
    which functions are visible to users of the module.

    Module scope variables (prefixed with $script:) are private to the module
    and persist across function calls within the same session.

    LOG LEVELS:
    -----------
    - DEBUG:   Detailed diagnostic information (gray) - for developers
    - INFO:    General informational messages (white) - normal operations
    - SUCCESS: Successful operations (green) - completion of important steps
    - WARN:    Warning conditions (yellow) - something unexpected but not fatal
    - ERROR:   Error conditions (red) - something failed

.EXAMPLE
    # Import the module
    Import-Module C:\Lab\scripts\modules\Logger.psm1

    # Initialize logging for your script
    Initialize-Logging -ScriptName "dc-setup"

    # Write log messages
    Write-Log "Starting Active Directory setup" -Level INFO
    Write-Log "Installing AD DS role..." -Level INFO
    Write-Log "AD DS role installed successfully" -Level SUCCESS
    Write-Log "DNS configuration may need adjustment" -Level WARN
    Write-Log "Failed to create user: $($_.Exception.Message)" -Level ERROR

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    POWERSHELL CONCEPTS USED:
    - Module scope variables ($script:)
    - Parameter validation ([ValidateSet])
    - Here-strings (@" "@ and @' '@)
    - Splatting (@params)
    - Pipeline operations
#>

# =============================================================================
# MODULE-LEVEL VARIABLES
# =============================================================================
# These variables are scoped to the module ($script:) which means they:
# - Are NOT visible outside the module
# - Persist across function calls
# - Are shared between all functions in this module

# Default log directory - can be overridden in Initialize-Logging
$script:LogPath = "C:\Lab\logs"

# Current log file path - set by Initialize-Logging
$script:LogFile = $null

# Flag to track if logging has been initialized
$script:IsInitialized = $false

# =============================================================================
# PUBLIC FUNCTIONS
# =============================================================================

function Initialize-Logging {
    <#
    .SYNOPSIS
        Initializes the logging system for a script.

    .DESCRIPTION
        This function MUST be called at the start of each script before using
        Write-Log. It:
        1. Creates the log directory if it doesn't exist
        2. Creates a new log file with timestamp in the name
        3. Writes a header to the log file

        WHY INITIALIZE?
        ---------------
        We initialize logging explicitly rather than auto-initializing because:
        - Different scripts need different log file names
        - We want a clear timestamp when the script started
        - We can customize the log path per-script if needed

    .PARAMETER ScriptName
        The name of the calling script. This becomes part of the log filename.
        Example: "dc-setup" creates "dc-setup-20260127-143052.log"

    .PARAMETER LogDirectory
        Optional. Override the default log directory (C:\Lab\logs).
        Useful for separating logs by component or for testing.

    .EXAMPLE
        Initialize-Logging -ScriptName "Install-ADDS"
        # Creates: C:\Lab\logs\Install-ADDS-20260127-143052.log

    .EXAMPLE
        Initialize-Logging -ScriptName "sql-setup" -LogDirectory "D:\SQLLogs"
        # Creates: D:\SQLLogs\sql-setup-20260127-143052.log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptName,

        [Parameter(Mandatory = $false)]
        [string]$LogDirectory = $script:LogPath
    )

    # Update the log path if a custom directory was specified
    $script:LogPath = $LogDirectory

    # Create log directory if it doesn't exist
    # The -Force parameter prevents errors if the directory already exists
    # Out-Null suppresses the output (we don't need to see the DirectoryInfo object)
    if (-not (Test-Path $script:LogPath)) {
        New-Item -ItemType Directory -Path $script:LogPath -Force | Out-Null
    }

    # Create log file with timestamp
    # Format: ScriptName-YYYYMMDD-HHMMSS.log
    # This ensures unique filenames and makes it easy to sort chronologically
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = Join-Path $script:LogPath "$ScriptName-$timestamp.log"

    # Mark as initialized
    $script:IsInitialized = $true

    # Write log header
    # The @" "@ syntax is a "here-string" - it preserves formatting and newlines
    $header = @"
================================================================================
SCCM Lab Automation Log
================================================================================
Script:     $ScriptName
Started:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer:   $env:COMPUTERNAME
User:       $env:USERDOMAIN\$env:USERNAME
PowerShell: $($PSVersionTable.PSVersion)
================================================================================

"@

    # Write header to log file
    # Set-Content creates or overwrites the file
    Set-Content -Path $script:LogFile -Value $header -Encoding UTF8

    # Also write to console
    Write-Host $header -ForegroundColor Cyan

    # Log that we initialized (using our own function!)
    Write-Log "Logging initialized: $($script:LogFile)" -Level DEBUG
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped log message to console and file.

    .DESCRIPTION
        This is the primary logging function. It writes messages with:
        - Timestamp (for chronological tracking)
        - Level indicator (for filtering and visual scanning)
        - Color coding (for quick visual identification in console)
        - File output (for permanent record)

        HOW THE LOG FORMAT WORKS:
        -------------------------
        Each line is formatted as:
        [2026-01-27 14:30:45] [INFO   ] Your message here

        The timestamp uses ISO 8601-ish format for unambiguous dates.
        The level is padded to 7 characters for alignment.

    .PARAMETER Message
        The message to log. Can include variable expansion.

    .PARAMETER Level
        The severity level. Determines color and can be used for filtering.
        Valid values: DEBUG, INFO, SUCCESS, WARN, ERROR

    .EXAMPLE
        Write-Log "Starting installation"
        # Output: [2026-01-27 14:30:45] [INFO   ] Starting installation

    .EXAMPLE
        Write-Log "Feature installed successfully" -Level SUCCESS
        # Output (green): [2026-01-27 14:30:45] [SUCCESS] Feature installed successfully

    .EXAMPLE
        Write-Log "Retrying connection (attempt 3/5)" -Level WARN
        # Output (yellow): [2026-01-27 14:30:45] [WARN   ] Retrying connection (attempt 3/5)

    .EXAMPLE
        try {
            # Something that might fail
        } catch {
            Write-Log "Operation failed: $($_.Exception.Message)" -Level ERROR
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]  # Allow empty strings (sometimes useful for blank lines)
        [string]$Message,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    # Get current timestamp
    # Format: 2026-01-27 14:30:45
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Define colors for each level
    # This hashtable maps level names to console colors
    $colors = @{
        'DEBUG'   = 'Gray'      # Subtle, for verbose output
        'INFO'    = 'White'     # Normal text
        'SUCCESS' = 'Green'     # Good things!
        'WARN'    = 'Yellow'    # Pay attention
        'ERROR'   = 'Red'       # Something broke
    }

    # Format the log line
    # PadRight(7) ensures all levels are the same width:
    # "INFO" becomes "INFO   " (7 chars)
    # "SUCCESS" stays "SUCCESS" (7 chars)
    # This keeps the messages aligned
    $logLine = "[$timestamp] [$($Level.PadRight(7))] $Message"

    # Write to console with appropriate color
    Write-Host $logLine -ForegroundColor $colors[$Level]

    # Write to file if logging is initialized
    # We use Add-Content to append (not overwrite) the file
    if ($script:IsInitialized -and $script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logLine -Encoding UTF8
    }
}

function Write-LogSection {
    <#
    .SYNOPSIS
        Writes a section header to visually separate parts of the log.

    .DESCRIPTION
        Long scripts benefit from visual separation between major sections.
        This function writes a formatted header that stands out in both
        console output and log files.

        Output looks like:
        ============================================================
        Installing SQL Server
        ============================================================

    .PARAMETER Title
        The section title to display.

    .EXAMPLE
        Write-LogSection "Phase 1: Install Prerequisites"
        Write-Log "Installing .NET Framework..."
        # ... more operations ...

        Write-LogSection "Phase 2: Configure Services"
        Write-Log "Configuring SQL Server..."
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Title
    )

    # Create a separator line of equals signs
    # 60 characters is wide enough to be visible but not too wide
    $separator = "=" * 60

    # Write blank line for spacing
    Write-Log "" -Level INFO

    # Write the section header
    Write-Log $separator -Level INFO
    Write-Log $Title -Level INFO
    Write-Log $separator -Level INFO

    # Write blank line after for spacing
    Write-Log "" -Level INFO
}

function Write-LogError {
    <#
    .SYNOPSIS
        Writes detailed error information to the log.

    .DESCRIPTION
        When an error occurs, you often need more than just the message.
        This function extracts and logs:
        - The error message
        - The exception type
        - The script location where the error occurred
        - The full stack trace (for debugging)

        This is especially useful in try/catch blocks.

    .PARAMETER ErrorRecord
        The error record to log. In a catch block, use $_ or $Error[0].

    .PARAMETER Message
        Optional custom message to prepend to the error details.

    .EXAMPLE
        try {
            Get-Content "C:\nonexistent\file.txt" -ErrorAction Stop
        } catch {
            Write-LogError -ErrorRecord $_ -Message "Failed to read configuration"
        }

        # Output:
        # [ERROR  ] Failed to read configuration
        # [ERROR  ] Exception: System.Management.Automation.ItemNotFoundException
        # [ERROR  ] Message: Cannot find path 'C:\nonexistent\file.txt'
        # [ERROR  ] Location: Script.ps1: Line 42
        # [DEBUG  ] Stack trace: at <ScriptBlock>, Script.ps1: line 42
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory = $false)]
        [string]$Message = "An error occurred"
    )

    # Write the custom message
    Write-Log $Message -Level ERROR

    # Write exception type (helps identify what kind of error)
    Write-Log "Exception: $($ErrorRecord.Exception.GetType().FullName)" -Level ERROR

    # Write the actual error message
    Write-Log "Message: $($ErrorRecord.Exception.Message)" -Level ERROR

    # Write the location in the script where the error occurred
    # InvocationInfo contains details about where the error happened
    if ($ErrorRecord.InvocationInfo) {
        $location = "$($ErrorRecord.InvocationInfo.ScriptName): Line $($ErrorRecord.InvocationInfo.ScriptLineNumber)"
        Write-Log "Location: $location" -Level ERROR
    }

    # Write stack trace at DEBUG level (verbose, but useful for debugging)
    if ($ErrorRecord.ScriptStackTrace) {
        Write-Log "Stack trace: $($ErrorRecord.ScriptStackTrace)" -Level DEBUG
    }
}

function Get-LogPath {
    <#
    .SYNOPSIS
        Returns the path to the current log file.

    .DESCRIPTION
        Useful when you need to tell the user where to find logs,
        or when you need to process the log file after script completion.

    .EXAMPLE
        Write-Host "Log file: $(Get-LogPath)"

    .OUTPUTS
        String - The full path to the current log file, or $null if not initialized.
    #>
    [CmdletBinding()]
    param()

    return $script:LogFile
}

function Complete-Logging {
    <#
    .SYNOPSIS
        Finalizes logging and writes a completion message.

    .DESCRIPTION
        Call this at the end of your script to write a clean footer
        showing the script completed (or failed) and the total runtime.

    .PARAMETER Success
        Whether the script completed successfully. Affects the message color.

    .EXAMPLE
        # At the end of your script:
        Complete-Logging -Success $true

        # Or in a finally block:
        try {
            # ... script logic ...
            $scriptSuccess = $true
        } catch {
            $scriptSuccess = $false
            throw
        } finally {
            Complete-Logging -Success $scriptSuccess
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$Success = $true
    )

    # Calculate how long the script has been running
    # We can get this from the log file creation time
    $duration = "Unknown"
    if ($script:LogFile -and (Test-Path $script:LogFile)) {
        $startTime = (Get-Item $script:LogFile).CreationTime
        $elapsed = (Get-Date) - $startTime
        $duration = "{0:hh\:mm\:ss}" -f $elapsed
    }

    # Write completion footer
    $status = if ($Success) { "COMPLETED SUCCESSFULLY" } else { "COMPLETED WITH ERRORS" }
    $level = if ($Success) { "SUCCESS" } else { "ERROR" }

    Write-Log "" -Level INFO
    Write-Log ("=" * 60) -Level INFO
    Write-Log "Script $status" -Level $level
    Write-Log "Duration: $duration" -Level INFO
    Write-Log "Log file: $($script:LogFile)" -Level INFO
    Write-Log ("=" * 60) -Level INFO
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================
# Export-ModuleMember controls which functions are visible when someone imports
# this module. Functions not listed here are "private" to the module.
#
# We export all public functions. The module-level variables ($script:*) remain
# private and can only be accessed through these functions.

Export-ModuleMember -Function @(
    'Initialize-Logging',
    'Write-Log',
    'Write-LogSection',
    'Write-LogError',
    'Get-LogPath',
    'Complete-Logging'
)
