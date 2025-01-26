# Docker Project Updater Script
# Optimized for PowerShell 7.x

# Configuration
$script:config = @{
    BackupRetention = 2  # Number of backups to keep
    TimeFormat      = "dd-MM-yyyy hh:mm tt"
}

# Visual Style Functions
function Write-StatusLine {
    param (
        [string]$Message,
        [string]$Status = "INFO",
        [int]$IndentLevel = 0
    )

    $indent           = "   " * $IndentLevel
    $timestamp        = Get-Date -Format $config.TimeFormat
    $timestampDisplay = "[$timestamp]"

    switch ($Status) {
        "SUCCESS" {
            Write-Host $timestampDisplay -NoNewline
            Write-Host "[SUCCESS] " -NoNewline -ForegroundColor Green
            Write-Host "$indent$Message"
        }
        "ERROR" {
            Write-Host "$timestampDisplay[ERROR] $indent$Message" -ForegroundColor Red
        }
        "WARNING" {
            Write-Host $timestampDisplay -NoNewline
            Write-Host "[WARNING] " -NoNewline -ForegroundColor Yellow
            Write-Host "$indent$Message"
        }
        "INFO" {
            Write-Host $timestampDisplay -NoNewline
            Write-Host "[INFO] " -NoNewline -ForegroundColor Cyan
            Write-Host "$indent$Message"
        }
        "PROGRESS" {
            Write-Host $timestampDisplay -NoNewline
            Write-Host "[PROGRESS] " -NoNewline -ForegroundColor Blue
            Write-Host "$indent$Message"
        }
    }
}

function Write-Header {
    param ([string]$Title)

    $headerWidth = 80
    $padding     = [math]::Max(0, ($headerWidth - $Title.Length - 6) / 2)
    $paddingStr  = "=" * [math]::Floor($padding)

    Write-Host "`n$paddingStr>>> $Title <<<$paddingStr" -ForegroundColor Cyan
    Write-Host "=" * $headerWidth -ForegroundColor Blue
    Write-Host ""
}

function ConvertFrom-DockerSize {
    param ([string]$size)

    if ($size -match "(\d+\.?\d*)(\w+)") {
        $value = [double]$matches[1]
        $unit  = $matches[2].ToLower()

        switch ($unit) {
            "b" { return $value }
            "kb" { return $value * 1024 }
            "mb" { return $value * 1024 * 1024 }
            "gb" { return $value * 1024 * 1024 * 1024 }
            "tb" { return $value * 1024 * 1024 * 1024 * 1024 }
            default { return $value }
        }
    }
    return 0
}

function Invoke-DockerCommand {
    param (
        [string]$Command,
        [string]$Description,
        [switch]$ShowProgress
    )

    Write-StatusLine "$Description" -Status "INFO"

    # Initialize variables for progress tracking
    $script:currentStep = 0
    $script:totalSteps = 0
    $script:lastLine = ""
    $script:avgProgress = 0
    $stdOutputBuffer = New-Object System.Collections.ArrayList # Buffer for standard output
    $stdErrorBuffer = New-Object System.Collections.ArrayList  # Buffer for standard error

    try {
        # Start the process and capture output streams
        $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processStartInfo.FileName = "pwsh.exe"
        $processStartInfo.Arguments = "-NoProfile -Command ""$Command"""
        $processStartInfo.RedirectStandardOutput = $true
        $processStartInfo.RedirectStandardError = $true
        $processStartInfo.UseShellExecute = $false
        $processStartInfo.CreateNoWindow = $true

        # Construct command WITH global --progress=plain for BUILD commands
        $commandToExecute = "pwsh.exe -NoProfile -Command ""$Command"""
        if ($Description -like "*Building containers*") {
            $commandToExecute = "pwsh.exe -NoProfile -Command ""docker compose --progress=plain $($Command.Replace('docker compose',''))""" # Corrected --progress placement
        }

        $process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoProfile", "-Command", $commandToExecute -NoNewWindow -PassThru # Removed -Wait and -LineBuffered for now

        # Output data event handlers for real-time output (Simplified handler - just buffer)
        $outputHandler = {
            param([object]$processSender, [System.Diagnostics.DataReceivedEventArgs]$processEventArgs)
            if ($processEventArgs.Data) {
                $stdOutputBuffer.Add($processEventArgs.Data) # Buffer standard output lines
                Format-DockerOutputLine -line $processEventArgs.Data # Still format and display in real-time
            }
        }
        $errorHandler = { # New event handler for ErrorDataReceived
            param([object]$processSender, [System.Diagnostics.DataReceivedEventArgs]$processEventArgs)
            if ($processEventArgs.Data) {
                $stdErrorBuffer.Add($processEventArgs.Data) # Buffer error output lines
                Write-Host "ERROR OUTPUT: $($processEventArgs.Data)" -ForegroundColor Red # Display error output in red
            }
        }

        Register-ObjectEvent -InputObject $process -EventName 'OutputDataReceived' -Action $outputHandler | Out-Null
        Register-ObjectEvent -InputObject $process -EventName 'ErrorDataReceived' -Action $errorHandler | Out-Null # Register error handler

        # Begin asynchronous read of output and error streams
        try {
            $process.BeginOutputReadLine()
        } catch {
            # Suppress "BeginOutputReadLine" errors if they occur (likely benign)
            Write-StatusLine "Suppressed BeginOutputReadLine Error (StandardOutput): $($_.Exception.Message)" -Status "WARNING"
        }
        try {
             $process.BeginErrorReadLine()
        } catch {
            # Suppress "BeginOutputReadLine" errors if they occur (likely benign)
            Write-StatusLine "Suppressed BeginOutputReadLine Error (StandardError): $($_.Exception.Message)" -Status "WARNING"
        }


        # Wait for process to exit
        $process.WaitForExit()

        # --- ROBUST ERROR CHECKING ---
        $commandSuccess = $true # Assume success initially

        if ($process.ExitCode -ne 0) { # Check exit code FIRST
            Write-StatusLine "Command exited with code $($process.ExitCode)" -Status "WARNING" # Warning, not Error yet - check output

            if ($Description -like "*Building containers*") { # Special success check for build command
                $buildOutput = $stdOutputBuffer -join "`n" # Get buffered standard output
                if ($buildOutput -notmatch '(?smi)Service \w+\s+Built') { # More robust regex for "Service <name> Built"
                    Write-StatusLine "Docker Build Output does NOT contain 'Service <service_name> Built' - Build FAILED" -Status "ERROR" -ForegroundColor Red
                    $commandSuccess = $false # Explicitly set to failure
                } else {
                    Write-StatusLine "Docker Build Output CONTAINS 'Service <service_name> Built' - Build SUCCESSFUL (despite exit code)" -Status "SUCCESS" -ForegroundColor Green
                    $commandSuccess = $true # Build is considered successful based on output
                }
            } else { # For other commands, rely on exit code AND check for errors in error stream
                 if ($stdErrorBuffer.Count -gt 0) { # Check if anything was written to error stream
                    Write-StatusLine "Standard Error stream is NOT empty - Command FAILED" -Status "ERROR" -ForegroundColor Red
                    $commandSuccess = $false
                } else {
                     Write-StatusLine "Standard Error stream is empty, Exit Code is non-zero, but proceeding cautiously..." -Status "WARNING" # Still non-zero exit, but no error output - proceed cautiously
                     $commandSuccess = $true # Proceed cautiously, might be a false negative exit code
                }
            }

        } else { # Exit code IS zero - command *should* be successful
            Write-StatusLine "Command exited with code 0 (SUCCESS)" -Status "SUCCESS"
            $commandSuccess = $true # Exit code is 0, command is successful
        }


        if ($commandSuccess) {
             Write-StatusLine "$Description completed (with status check) - SUCCESS" -Status "SUCCESS"
             return $true # Return success
        } else {
             Write-StatusLine "$Description completed (with status check) - FAILED" -Status "ERROR" -ForegroundColor Red
             return $false # Return failure
        }


    }
    catch {
        Write-StatusLine "Error executing Docker command: $($_.Exception.Message)" -Status "ERROR"
        return $false
    }
    finally {
        if ($process) {
            $process.Dispose()
        }
        Unregister-Event -SourceIdentifier * -ErrorAction SilentlyContinue # Clean up event handlers
    }
}

function Format-DockerOutputLine { # Function name changed to use approved verb
    param($line)
    # Debug output to check if lines are received in real-time
    $currentTime = Get-Date -Format "hh:mm:ss.fff" # Add milliseconds for finer granularity
    Write-Host "DEBUG [$currentTime]: Received line: [$line]"
    #Write-Host "RAW: $line" # Keep RAW output for deeper debugging if needed

    switch -Regex ($line) {
        # Step progress (e.g., "Step 3/10")
        "^Step (\d+)/(\d+)\s*:" {
            $script:currentStep = [int]$matches[1]
            $script:totalSteps = [int]$matches[2]
            $script:buildPercent = [math]::Min(($script:currentStep / $script:totalSteps) * 100, 100)
            Write-StatusLine "Docker Build: Step $script:currentStep of $script:totalSteps ($script:buildPercent%)" -Status "PROGRESS"
            Write-Host $line  # Show the full step line
        }

        # Layer download progress
        "(\w+): (?:Pulling|Downloading) \[([=>-]+)\]\s+(\d+\.\d+\w+)/(\d+\.\d+\w+)" {
            $layer = $matches[1]
            $current = ConvertFrom-DockerSize $matches[3]
            $total = ConvertFrom-DockerSize $matches[4]
            $percent = [math]::Min(($current / $total) * 100, 100)
            Write-StatusLine "Downloading Layer: $layer ($percent%)" -Status "PROGRESS"
        }

        # Build output (captures RUN, COPY, ADD commands etc.)
        "^ ---> .*" {
            Write-Host $line
        }

        # Show output from build steps
        "^#\d+\s+\[.*?\]\s+" {
            Write-Host $line
        }

        # Default output - show everything except empty lines
        default {
            if (![string]::IsNullOrWhiteSpace($line)) {
                Write-Host $line
            }
        }
    }
}

function Test-DockerProject {
    param ([string]$ProjectPath)

    # Convert path to absolute and normalize
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)

    # Check compose files with detailed logging
    $composeFiles = @("docker-compose.yml", "docker-compose.yaml")
    $foundFile    = $null
    $envPath      = Join-Path $ProjectPath ".env"

    Write-StatusLine "Checking for compose files at: $ProjectPath" -Status "INFO"

    foreach ($file in $composeFiles) {
        $fullPath = Join-Path $ProjectPath $file
        if (Test-Path $fullPath -PathType Leaf) {
            $foundFile = $file
            Write-StatusLine "Found $file at: $fullPath" -Status "INFO"

            # Validate compose file contents
            try {
                $composeContent = Get-Content $fullPath -Raw
                if (-not ($composeContent -match 'services:')) {
                    Write-StatusLine "Invalid docker-compose file format in $file" -Status "WARNING"
                    $foundFile = $null
                    continue
                }
                break
            }
            catch {
                Write-StatusLine "Failed to read compose file: $($_.Exception.Message)" -Status "WARNING"
                $foundFile = $null
                continue
            }
        }
    }

    $envExists = Test-Path $envPath -PathType Leaf

    return @{
        IsDockerProject = ($null -ne $foundFile)
        HasEnv          = $envExists
        ComposeFile     = $foundFile
        ProjectPath     = $ProjectPath
    }
}

function Backup-DockerProject {
    param (
        [string]$ProjectPath,
        [string]$ProjectName
    )

    try {
        # Initialize
        $timestamp  = Get-Date -Format "dd-MM-yyyy_HH-mm"
        $backupRoot = Join-Path -Path $ProjectPath -ChildPath "backups"
        $backupDir  = Join-Path -Path $backupRoot -ChildPath $timestamp

        # Create directories
        if (-not (Test-Path $backupRoot)) {
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        }
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

        # Check project structure
        $projectFiles = Test-DockerProject $ProjectPath
        if (-not $projectFiles.IsDockerProject) {
            throw "Invalid Docker project structure"
        }

        # Backup compose file
        if ($projectFiles.ComposeFile) {
            $sourceCompose = Join-Path -Path $ProjectPath -ChildPath $projectFiles.ComposeFile
            $destCompose   = Join-Path -Path $backupDir -ChildPath $projectFiles.ComposeFile
            Copy-Item -Path $sourceCompose -Destination $destCompose -Force
            Write-StatusLine "Backed up compose file" -Status "INFO" -IndentLevel 1
        }

        # Backup env file
        if ($projectFiles.HasEnv) {
            $sourceEnv = Join-Path -Path $ProjectPath -ChildPath ".env"
            $destEnv   = Join-Path -Path $backupDir -ChildPath ".env"
            Copy-Item -Path $sourceEnv -Destination $destEnv -Force
            Write-StatusLine "Backed up environment file" -Status "INFO" -IndentLevel 1
        }

        # Cleanup old backups
        $allBackups = Get-ChildItem -Path $backupRoot -Directory | Sort-Object CreationTime -Descending
        if ($allBackups.Count -gt $config.BackupRetention) {
            $allBackups | Select-Object -Skip $config.BackupRetention | ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force
                Write-StatusLine "Removed old backup: $($_.Name)" -Status "INFO" -IndentLevel 1
            }
        }

        # Complete
        Write-StatusLine "Backup created successfully at $timestamp" -Status "SUCCESS"
        return $true
    }
    catch {
        Write-StatusLine "Backup failed: $($_.Exception.Message)" -Status "ERROR"
        return $false
    }
}

function Update-DockerProject {
    param (
        [string]$ProjectPath,
        [string]$ProjectName
    )

    try {
        Write-Header "Updating $ProjectName"

        # Validate project
        $projectFiles = Test-DockerProject $ProjectPath
        if (-not $projectFiles.IsDockerProject) {
            throw "Not a valid Docker project"
        }

        # Create backup
        if (-not (Backup-DockerProject -ProjectPath $ProjectPath -ProjectName $ProjectName)) {
            throw "Backup failed"
        }

        # Git operations
        Push-Location $ProjectPath

        # Fetch updates
        Write-StatusLine "Fetching latest updates..." -Status "INFO"
        $null = & git fetch --all 2>&1

        # Check for updates
        $status = & git status -uno
        if ($status -match "Your branch is up to date") {
            # No new updates - display message in RED
            Write-Host "[$((Get-Date).ToString($config.TimeFormat))][INFO]   No new updates available from GitHub" -ForegroundColor Red
            # Ask for rebuild
            $rebuildChoice = Read-Host "Would you like to rebuild the Docker containers anyway? (Y/N)"
            if ($rebuildChoice -ne 'Y') {
                Write-StatusLine "Skipping rebuild process" -Status "INFO"
                return $true # Exit if user does not want to rebuild
            }
        }
        else {
            # Handle updates
            Write-StatusLine "New updates available from GitHub" -Status "INFO" -ForegroundColor Green
            $pullOutput = & git pull 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Git pull failed: $pullOutput"
            }

            Write-StatusLine "Successfully pulled latest changes" -Status "SUCCESS"
        }

        # If we reach here, either there were updates or the user chose to rebuild
        Write-StatusLine "Initiating Docker operations..." -Status "INFO"

        # Docker operations
        try {
            # Check if docker-compose file exists
            $composePath = Join-Path $ProjectPath $projectFiles.ComposeFile
            $composePath = [System.IO.Path]::GetFullPath($composePath)
            Write-StatusLine "Checking for compose file at: $composePath" -Status "INFO"
            if (-not (Test-Path $composePath)) {
                Write-StatusLine "No docker-compose file found at $composePath" -Status "ERROR" -ForegroundColor Red
                throw "Docker compose file not found"
            }
            Write-StatusLine "Found compose file at: $composePath" -Status "SUCCESS"

            # Check running containers
            Write-StatusLine "Inspecting container state" -Status "INFO"
            $containerInfo = & pwsh.exe -Command "docker ps -a --filter 'name=${ProjectName}' --format '{{.ID}} {{.State}}'" | Out-String
            Write-StatusLine "Container info: $containerInfo" -Status "INFO"

            $runningContainers = @()
            foreach ($line in $containerInfo -split "`n") {
                if ($line -match '^(\w+)\s+(running|restarting)') {
                    $runningContainers += $matches[1]
                }
            }

            # Stop running containers
            if ($runningContainers.Count -gt 0) {
                Write-StatusLine "Found ${runningContainers.Count} running containers" -Status "INFO"
                Write-StatusLine "Attempting to stop containers" -Status "INFO"

                # Try docker compose down with timeout
                $stopResult = Invoke-DockerCommand "docker compose -f '$composePath' down --timeout 10" "Stopping containers (with timeout)" -ShowProgress
                if (-not $stopResult) {
                    Write-StatusLine "Failed to stop containers with timeout, attempting force removal" -Status "WARNING"

                    # Try force removal
                    $stopResult = Invoke-DockerCommand "docker compose -f '$composePath' down --rmi local --volumes --remove-orphans" "Stopping containers (force removal)" -ShowProgress
                    if (-not $stopResult) {
                        Write-StatusLine "Failed to force remove containers, attempting direct stop" -Status "WARNING"

                        # Try direct docker stop (if containers are still running)
                        foreach ($containerId in $runningContainers) {
                            $stopResult = Invoke-DockerCommand "docker stop $containerId" "Stopping container $containerId directly" -ShowProgress
                            if (-not $stopResult) {
                                Write-StatusLine "Failed to stop container $containerId" -Status "ERROR"
                            }
                        }
                    }
                }

                # Verify if containers are stopped
                $stillRunning = & pwsh.exe -Command "docker ps -a --filter 'name=${ProjectName}' --format '{{.ID}}' | Where-Object { $_ }"
                if ($stillRunning) {
                    Write-StatusLine "Some containers are still running or not properly removed: $($stillRunning -join ',')" -Status "ERROR"
                    throw "Failed to stop or remove all containers"
                }
            } else {
                Write-StatusLine "No running containers found" -Status "INFO"
            }

            # Build containers
            Write-StatusLine "Starting container rebuild with --no-cache to ensure fresh build" -Status "INFO"
            Write-StatusLine "Build command: docker compose -f '$composePath' build --no-cache --pull" -Status "INFO"
            if (-not (Invoke-DockerCommand "docker compose -f '$composePath' build --no-cache --pull" "Building containers" -ShowProgress)) {
                Write-StatusLine "Build command failed - check Docker build output above for specific errors" -Status "ERROR"
                throw "Failed to build containers"
            }

            # Start containers
            if (-not (Invoke-DockerCommand "docker compose -f '$composePath' up -d" "Starting containers" -ShowProgress)) {
                throw "Failed to start containers"
            }

            Write-StatusLine "Rebuild completed successfully" -Status "SUCCESS"
        }
        catch {
            Write-StatusLine "Docker operation failed: $($_.Exception.Message)" -Status "ERROR"
            throw  # Re-throw the exception to be handled by Start-DockerProjectUpdate
        }

        Write-StatusLine "Update completed successfully" -Status "SUCCESS"
        return $true  # Indicate successful update
    }
    catch {
        Write-StatusLine "Update failed: $($_.Exception.Message)" -Status "ERROR"
        return $false  # Indicate update failure
    }
    finally {
        Pop-Location
    }
}
function Start-DockerProjectUpdate {
    param (
        [string[]]$ProjectPaths
    )

    try {
        Write-Header "Docker Project Update Tool"

        # Validate Docker installation and check if Docker is running
        Write-StatusLine "Checking Docker installation and daemon status..." -Status "INFO"
        while ($true) { # Loop until Docker is running or user chooses to exit
            try {
                # Check if docker command is available and daemon is running
                & docker info > $null 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "Docker daemon not running or not accessible."
                }
                $dockerVersion = & pwsh.exe -Command "docker --version"
                $composeVersion = & pwsh.exe -Command "docker compose version"
                Write-StatusLine "Docker version: $dockerVersion" -Status "INFO"
                Write-StatusLine "Docker Compose version: $composeVersion" -Status "INFO"
                break  # Break out of the loop if Docker commands are successful
            }
           catch {
                Write-StatusLine "Docker check failed: $($_.Exception.Message)" -Status "ERROR" -ForegroundColor Red
                Write-Host "[$((Get-Date).ToString($config.TimeFormat))][ERROR] Error: Docker daemon may not be running or accessible." -ForegroundColor Red
                Write-Host "[$((Get-Date).ToString($config.TimeFormat))][ERROR] Please ensure Docker Desktop or Docker service is started." -ForegroundColor Red
                $choice = Read-Host "Try again (Y/N)?"
                if ($choice -ne 'Y') {
                    return # Exit the function if user chooses not to retry
                }
            }
        }

        # If we reach here, Docker is running, so proceed with project updates
        foreach ($projectPath in $ProjectPaths) {
            $projectName = Split-Path $projectPath -Leaf
            Write-StatusLine "Processing project: $projectName" -Status "INFO"

            if (-not (Test-Path $projectPath)) {
                Write-StatusLine "Project path not found: $projectPath" -Status "ERROR"
                continue
            }

            # Update the project (this function will only be called if Docker is running)
            $result = Update-DockerProject -ProjectPath $projectPath -ProjectName $projectName

            if (-not $result) {
                Write-StatusLine "Failed to update $projectName" -Status "ERROR"
                $choice = Read-Host "Continue with next project? (Y/N)"
                if ($choice -ne 'Y') {
                    break  # Exit the loop if the user chooses not to continue
                }
            }
            else {
                # Show final status with fresh project validation
                $currentProjectFiles = Test-DockerProject $ProjectPath
                if ($currentProjectFiles.IsDockerProject -and $currentProjectFiles.ComposeFile) {
                    $composePath = Join-Path $ProjectPath $currentProjectFiles.ComposeFile
                    if (Test-Path $composePath) {
                        Write-StatusLine "Checking final status for $projectName" -Status "INFO"
                        try {
                            Write-Host "`nContainer Status:" -ForegroundColor Cyan
                            try {
                                Write-StatusLine "Checking container status..." -Status "INFO"
                                Push-Location $ProjectPath
                                try {
                                    $status = & pwsh.exe -Command "docker compose -f '$composePath' ps --format 'table {{.Name}}\t{{.State}}\t{{.Ports}}'"
                                    if ($status -and $status.Count -gt 1) {
                                        Write-Host $status
                                        Write-StatusLine "Container status check completed" -Status "SUCCESS"
                                    }
                                    else {
                                        Write-StatusLine "No active containers found" -Status "INFO"
                                    }
                                }
                                catch {
                                    Write-StatusLine "Error checking container status: $_" -Status "WARNING"
                                }
                                finally {
                                    Pop-Location
                                }
                            }
                            catch {
                                Write-StatusLine "Failed to check container status: $($_.Exception.Message)" -Status "WARNING"
                            }

                            Write-Host "`nRecent Logs:" -ForegroundColor Cyan
                            try {
                                Write-StatusLine "Collecting recent logs..." -Status "INFO"
                                try {
                                    # Use docker compose for compatibility
                                    $logs = & pwsh.exe -Command "docker compose -f '$composePath' logs --tail=20"
                                    if ($logs) {
                                        Write-Host $logs
                                        Write-StatusLine "Log collection completed" -Status "SUCCESS"
                                    }
                                    else {
                                        Write-StatusLine "No container logs available" -Status "INFO"
                                    }
                                    Write-Host "`nStatus check completed. Press Ctrl+C to exit." -ForegroundColor Green
                                }
                                catch {
                                    Write-StatusLine "Error retrieving logs: $_" -Status "WARNING"
                                    Write-Host "`nStatus check completed with errors. Press Ctrl+C to exit." -ForegroundColor Red
                                }
                            }
                            catch {
                                Write-StatusLine "Failed to retrieve logs: $($_.Exception.Message)" -Status "WARNING"
                                Write-Host "`nStatus check completed with some warnings. Press Ctrl+C to exit." -ForegroundColor Yellow
                            }
                        }
                        catch {
                            Write-StatusLine "Status check failed: $($_.Exception.Message)" -Status "ERROR"
                        }
                    }
                    else {
                        $fullComposePath = [System.IO.Path]::GetFullPath($composePath)
                        Write-StatusLine "Cannot check status - docker-compose file not found at $fullComposePath" -Status "WARNING"
                    }
                }
                else {
                    Write-StatusLine "Skipping status check - invalid Docker project structure" -Status "WARNING"
                }
            }
        }
    }
    catch {
        Write-StatusLine "Error in main execution: $($_.Exception.Message)" -Status "ERROR"
        return # Exit the function if there is any error in the main execution
    }
    finally {
        Write-Header "Update Process Completed - ALL PROJECTS" # More explicit completion message!
        Read-Host "`nPress Enter to exit" # Added pause here!
    }
}
# Function to test the script configuration
function Test-ScriptConfiguration {
    param (
        [string]$ProjectPath
    )

    Write-Header "Testing Script Configuration"

    # Test Docker installation
    Write-StatusLine "Testing Docker installation..." -Status "INFO"
    try {
        # Check if docker command is available and daemon is running
        & docker info > $null 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Docker daemon not running or not accessible."
        }
        $dockerVersion = & pwsh.exe -Command "docker version --format '{{.Server.Version}}'"
        Write-StatusLine "Docker version: $dockerVersion" -Status "SUCCESS"
    }
    catch {
        Write-StatusLine "Docker not running or not installed" -Status "ERROR"  # Docker not running error message in RED
        return
    }

    # Test project structure
    Write-StatusLine "Testing project structure..." -Status "INFO"
    $projectFiles = Test-DockerProject $ProjectPath
    if ($projectFiles.IsDockerProject) {
        Write-StatusLine "Valid Docker project structure found" -Status "SUCCESS"
    }
    else {
        Write-StatusLine "Invalid project structure" -Status "ERROR"
        return
    }

    Write-StatusLine "Configuration test completed" -Status "SUCCESS"
}

# Usage Example - Uncomment and modify the path to use
$projectPaths = @(
    "C:\Users\jovin\Documents\GitHub\web-ui"
    "C:\Users\jovin\Documents\GitHub\ollama-straico-apiproxy"
)

# To run the script, uncomment one of these lines:
Start-DockerProjectUpdate -ProjectPaths $projectPaths  # For full update
# Test-ScriptConfiguration -ProjectPath $projectPaths[0] # For testing configuration
