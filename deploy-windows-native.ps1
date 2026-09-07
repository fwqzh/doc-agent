[CmdletBinding()]
param(
    [ValidateSet("Deploy", "Setup", "Start", "Stop", "Restart", "Status", "Doctor")]
    [string]$Action = "Deploy",

    [switch]$WithoutDataProcess,
    [switch]$IncludeNorthbound,
    [switch]$SkipDatabaseInit,
    [switch]$SkipFrontendBuild,
    [switch]$NoOpen,
    [switch]$Force,
    [string]$EnvironmentFile = "",
    [string]$DataDirectory = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$NativeRoot = Join-Path $RepoRoot ".nexent-windows"
$RuntimeDirectory = Join-Path $NativeRoot "runtime"
$LogDirectory = Join-Path $NativeRoot "logs"
$PidFile = Join-Path $RuntimeDirectory "processes.json"
$EnvironmentTemplate = Join-Path $RepoRoot "deploy\windows-native\.env.example"

if ([string]::IsNullOrWhiteSpace($EnvironmentFile)) {
    $EnvironmentFile = Join-Path $NativeRoot ".env"
}
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $DataDirectory = Join-Path $NativeRoot "data"
}

function Write-Step {
    param([string]$Message)
    Write-Host "[nexent-windows] $Message" -ForegroundColor Cyan
}

function Resolve-Executable {
    param([string[]]$Names)

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }
    return $null
}

function Invoke-Checked {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$WorkingDirectory = $RepoRoot
    )

    Push-Location $WorkingDirectory
    try {
        & $Executable @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $Executable $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMilliseconds = 1200
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $result = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            return $false
        }
        $client.EndConnect($result)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Wait-TcpPort {
    param(
        [string]$Name,
        [int]$Port,
        [int]$TimeoutSeconds = 45
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort -HostName "127.0.0.1" -Port $Port) {
            Write-Host "  OK $Name is listening on port $Port" -ForegroundColor Green
            return
        }
        Start-Sleep -Milliseconds 500
    }
    throw "$Name did not start on port $Port within $TimeoutSeconds seconds. Check $LogDirectory."
}

function Set-DotEnvValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value
    )

    $escapedValue = $Value.Replace("`r", "").Replace("`n", "")
    $lines = @()
    if (Test-Path $Path) {
        $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    }

    $found = $false
    $updated = foreach ($line in $lines) {
        if ($line -match "^$([regex]::Escape($Key))=") {
            $found = $true
            "$Key=$escapedValue"
        }
        else {
            $line
        }
    }
    if (-not $found) {
        $updated += "$Key=$escapedValue"
    }
    [System.IO.File]::WriteAllLines($Path, [string[]]$updated, (New-Object System.Text.UTF8Encoding($false)))
}

function Import-DotEnv {
    param([string]$Path)

    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#") -or -not $trimmed.Contains("=")) {
            continue
        }
        $parts = $trimmed.Split("=", 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}

function Initialize-NativeEnvironment {
    New-Item -ItemType Directory -Force -Path $NativeRoot, $RuntimeDirectory, $LogDirectory, $DataDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDirectory "skills") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDirectory "official-skills-zip") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDirectory "memory-provider-plugins") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDirectory "workdir") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDirectory "uploads") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDirectory "libreoffice-profile") | Out-Null

    if (-not (Test-Path $EnvironmentFile)) {
        Copy-Item -LiteralPath $EnvironmentTemplate -Destination $EnvironmentFile
        Write-Host "  Created $EnvironmentFile" -ForegroundColor Green
    }

    Set-DotEnvValue -Path $EnvironmentFile -Key "ROOT_DIR" -Value $DataDirectory
    Set-DotEnvValue -Path $EnvironmentFile -Key "LOG_DIR" -Value $LogDirectory
    Set-DotEnvValue -Path $EnvironmentFile -Key "SKILLS_PATH" -Value (Join-Path $DataDirectory "skills")
    Set-DotEnvValue -Path $EnvironmentFile -Key "OFFICIAL_SKILLS_ZIP_PATH" -Value (Join-Path $DataDirectory "official-skills-zip")
    Set-DotEnvValue -Path $EnvironmentFile -Key "MEMORY_PROVIDER_PLUGINS_DIR" -Value (Join-Path $DataDirectory "memory-provider-plugins")
    Set-DotEnvValue -Path $EnvironmentFile -Key "AGENT_WORKSPACE_ROOT" -Value (Join-Path $DataDirectory "workdir")
    Set-DotEnvValue -Path $EnvironmentFile -Key "ALLOWED_SKILL_UPLOAD_ROOT" -Value $DataDirectory
    Set-DotEnvValue -Path $EnvironmentFile -Key "UPLOAD_FOLDER" -Value (Join-Path $DataDirectory "uploads")
    Set-DotEnvValue -Path $EnvironmentFile -Key "LIBREOFFICE_PROFILE_DIR" -Value (Join-Path $DataDirectory "libreoffice-profile")
    Set-DotEnvValue -Path $EnvironmentFile -Key "RAY_TEMP_DIR" -Value (Join-Path $DataDirectory "ray")
    Import-DotEnv -Path $EnvironmentFile
}

function Get-RequiredCommands {
    $commands = @(
        @{ Name = "Python 3.11"; Candidates = @("python.exe", "python") },
        @{ Name = "uv"; Candidates = @("uv.exe", "uv") },
        @{ Name = "Node.js"; Candidates = @("node.exe", "node") },
        @{ Name = "pnpm"; Candidates = @("pnpm.cmd", "pnpm.exe", "pnpm") },
        @{ Name = "PostgreSQL client"; Candidates = @("psql.exe", "psql") }
    )
    return $commands
}

function Invoke-Doctor {
    if ($env:OS -ne "Windows_NT") {
        throw "This entrypoint is intended for native Windows PowerShell."
    }

    Write-Step "Checking native Windows prerequisites"
    $missing = @()
    foreach ($item in (Get-RequiredCommands)) {
        $path = Resolve-Executable -Names $item.Candidates
        if ($null -eq $path) {
            Write-Host "  MISSING $($item.Name)" -ForegroundColor Red
            $missing += $item.Name
        }
        else {
            Write-Host "  OK $($item.Name): $path" -ForegroundColor Green
        }
    }

    $python = Resolve-Executable -Names @("python.exe", "python")
    if ($null -ne $python) {
        $pythonVersion = (& $python -c "import sys; print('.'.join(map(str, sys.version_info[:3])))").Trim()
        if ($LASTEXITCODE -ne 0 -or -not $pythonVersion.StartsWith("3.11.")) {
            Write-Host "  UNSUPPORTED Python: $pythonVersion (3.11.x required)" -ForegroundColor Red
            $missing += "Python 3.11.x"
        }
    }

    $node = Resolve-Executable -Names @("node.exe", "node")
    if ($null -ne $node) {
        $nodeVersionText = (& $node --version).Trim().TrimStart("v")
        $nodeVersion = $null
        if (-not [version]::TryParse($nodeVersionText, [ref]$nodeVersion) -or $nodeVersion -lt [version]"20.0.0") {
            Write-Host "  UNSUPPORTED Node.js: $nodeVersionText (20+ required)" -ForegroundColor Red
            $missing += "Node.js 20+"
        }
    }

    $services = @(
        @{ Name = "PostgreSQL"; Host = $env:POSTGRES_HOST; Port = [int]$env:POSTGRES_PORT },
        @{ Name = "Redis-compatible service"; Host = ([uri]$env:REDIS_URL).Host; Port = ([uri]$env:REDIS_URL).Port },
        @{ Name = "Elasticsearch"; Host = ([uri]$env:ELASTICSEARCH_HOST).Host; Port = ([uri]$env:ELASTICSEARCH_HOST).Port },
        @{ Name = "MinIO"; Host = ([uri]$env:MINIO_ENDPOINT).Host; Port = ([uri]$env:MINIO_ENDPOINT).Port }
    )
    foreach ($service in $services) {
        if (Test-TcpPort -HostName $service.Host -Port $service.Port) {
            Write-Host "  OK $($service.Name): $($service.Host):$($service.Port)" -ForegroundColor Green
        }
        else {
            Write-Host "  MISSING $($service.Name): $($service.Host):$($service.Port) is not reachable" -ForegroundColor Red
            $missing += $service.Name
        }
    }

    if ($missing.Count -gt 0) {
        $joined = $missing -join ", "
        throw "Native prerequisites are incomplete: $joined. See deploy/windows-native/README.md."
    }
}

function Install-ApplicationDependencies {
    Write-Step "Installing Python dependencies"
    $uv = Resolve-Executable -Names @("uv.exe", "uv")
    $uvArguments = @("sync")
    if (-not $WithoutDataProcess) {
        $uvArguments += @("--extra", "data-process")
    }
    Invoke-Checked -Executable $uv -Arguments $uvArguments -WorkingDirectory (Join-Path $RepoRoot "backend")
    Invoke-Checked -Executable $uv -Arguments @("pip", "install", "-e", "../sdk") -WorkingDirectory (Join-Path $RepoRoot "backend")

    Write-Step "Installing frontend dependencies"
    $pnpm = Resolve-Executable -Names @("pnpm.cmd", "pnpm.exe", "pnpm")
    $frontendDirectory = Join-Path $RepoRoot "frontend"
    $pnpmArguments = @("install")
    if (Test-Path (Join-Path $frontendDirectory "pnpm-lock.yaml")) {
        $pnpmArguments += "--frozen-lockfile"
    }
    Invoke-Checked -Executable $pnpm -Arguments $pnpmArguments -WorkingDirectory $frontendDirectory
    if (-not $SkipFrontendBuild) {
        Write-Step "Building the frontend"
        Invoke-Checked -Executable $pnpm -Arguments @("build") -WorkingDirectory $frontendDirectory
    }
}

function Initialize-DatabaseSchema {
    if ($SkipDatabaseInit) {
        Write-Host "  Database initialization skipped by request." -ForegroundColor Yellow
        return
    }

    Write-Step "Initializing the Nexent PostgreSQL schema"
    $psql = Resolve-Executable -Names @("psql.exe", "psql")
    $previousPassword = $env:PGPASSWORD
    $env:PGPASSWORD = $env:NEXENT_POSTGRES_PASSWORD
    try {
        & $psql -h $env:POSTGRES_HOST -p $env:POSTGRES_PORT -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -f (Join-Path $RepoRoot "deploy\sql\init.sql")
        if ($LASTEXITCODE -ne 0) {
            throw "PostgreSQL schema initialization failed. Create the configured role/database first, then retry."
        }
    }
    finally {
        $env:PGPASSWORD = $previousPassword
    }
}

function Read-ProcessRecords {
    if (-not (Test-Path $PidFile)) {
        return @()
    }
    $content = Get-Content -LiteralPath $PidFile -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($content)) {
        return @()
    }
    return @(ConvertFrom-Json $content)
}

function Test-OwnedProcess {
    param($Record)

    $process = Get-Process -Id $Record.pid -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return $false
    }
    try {
        return $process.StartTime.ToUniversalTime().ToString("o") -eq $Record.startTime
    }
    catch {
        return $false
    }
}

function Stop-NexentProcesses {
    Write-Step "Stopping native Nexent processes"
    $records = Read-ProcessRecords
    foreach ($record in $records) {
        if (Test-OwnedProcess -Record $record) {
            Stop-Process -Id $record.pid -Force:$Force
            Write-Host "  Stopped $($record.name) (PID $($record.pid))" -ForegroundColor Green
        }
        else {
            Write-Host "  Skipped stale PID record for $($record.name)" -ForegroundColor Yellow
        }
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

function Start-NativeProcess {
    param(
        [string]$Name,
        [string]$Executable,
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    $stdout = Join-Path $LogDirectory "$Name.out.log"
    $stderr = Join-Path $LogDirectory "$Name.err.log"
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    return [pscustomobject]@{
        name = $Name
        pid = $process.Id
        startTime = $process.StartTime.ToUniversalTime().ToString("o")
        stdout = $stdout
        stderr = $stderr
    }
}

function Start-NexentProcesses {
    Initialize-NativeEnvironment
    $existing = @(Read-ProcessRecords | Where-Object { Test-OwnedProcess -Record $_ })
    if ($existing.Count -gt 0) {
        throw "Nexent native processes are already running. Use -Action Status or -Action Restart."
    }

    $python = Join-Path $RepoRoot "backend\.venv\Scripts\python.exe"
    if (-not (Test-Path $python)) {
        throw "Backend virtual environment not found. Run -Action Setup or -Action Deploy first."
    }
    $node = Resolve-Executable -Names @("node.exe", "node")

    $services = @(
        @{ Name = "mcp"; File = "backend\mcp_service.py"; Port = 5011 },
        @{ Name = "config"; File = "backend\config_service.py"; Port = 5010 },
        @{ Name = "runtime"; File = "backend\runtime_service.py"; Port = 5014 }
    )
    if (-not $WithoutDataProcess) {
        $services += @{ Name = "data-process"; File = "backend\data_process_service.py"; Port = 5012 }
    }
    if ($IncludeNorthbound) {
        $services += @{ Name = "northbound"; File = "backend\northbound_service.py"; Port = 5013 }
    }

    foreach ($service in $services) {
        if (Test-TcpPort -HostName "127.0.0.1" -Port $service.Port) {
            throw "Port $($service.Port) required by $($service.Name) is already in use."
        }
    }
    if (Test-TcpPort -HostName "127.0.0.1" -Port 3000) {
        throw "Port 3000 required by the Nexent web application is already in use."
    }
    if (Test-TcpPort -HostName "127.0.0.1" -Port 5015) {
        throw "Port 5015 required by MCP management is already in use."
    }

    Write-Step "Starting native Nexent services"
    $records = @()
    try {
        foreach ($service in $services) {
            $records += Start-NativeProcess -Name $service.Name -Executable $python `
                -Arguments @($service.File) -WorkingDirectory $RepoRoot
            Wait-TcpPort -Name $service.Name -Port $service.Port
            if ($service.Name -eq "mcp") {
                Wait-TcpPort -Name "mcp-management" -Port 5015
            }
        }

        $previousNodeEnv = $env:NODE_ENV
        $env:NODE_ENV = "production"
        try {
            $records += Start-NativeProcess -Name "web" -Executable $node -Arguments @("server.js") `
                -WorkingDirectory (Join-Path $RepoRoot "frontend")
            Wait-TcpPort -Name "web" -Port 3000 -TimeoutSeconds 60
        }
        finally {
            $env:NODE_ENV = $previousNodeEnv
        }

        $records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $PidFile -Encoding UTF8
    }
    catch {
        foreach ($record in $records) {
            if (Test-OwnedProcess -Record $record) {
                Stop-Process -Id $record.pid -Force -ErrorAction SilentlyContinue
            }
        }
        throw
    }

    Write-Host "Nexent is available at http://localhost:3000" -ForegroundColor Green
    Write-Host "Runtime data: $NativeRoot"
    if (-not $NoOpen) {
        Start-Process "http://localhost:3000"
    }
}

function Show-NexentStatus {
    $records = Read-ProcessRecords
    if ($records.Count -eq 0) {
        Write-Host "No native Nexent process records were found." -ForegroundColor Yellow
        return
    }
    foreach ($record in $records) {
        $state = "stopped"
        if (Test-OwnedProcess -Record $record) {
            $state = "running"
        }
        Write-Host ("{0,-16} {1,-8} PID {2}" -f $record.name, $state, $record.pid)
    }
}

switch ($Action) {
    "Doctor" {
        Initialize-NativeEnvironment
        Invoke-Doctor
    }
    "Setup" {
        Initialize-NativeEnvironment
        Invoke-Doctor
        Install-ApplicationDependencies
        Initialize-DatabaseSchema
    }
    "Start" {
        Initialize-NativeEnvironment
        Invoke-Doctor
        Start-NexentProcesses
    }
    "Stop" {
        Stop-NexentProcesses
    }
    "Restart" {
        Stop-NexentProcesses
        Initialize-NativeEnvironment
        Invoke-Doctor
        Start-NexentProcesses
    }
    "Status" {
        Show-NexentStatus
    }
    "Deploy" {
        Initialize-NativeEnvironment
        Invoke-Doctor
        Install-ApplicationDependencies
        Initialize-DatabaseSchema
        Start-NexentProcesses
    }
}
