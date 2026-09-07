[CmdletBinding()]
param(
    [string]$ApiBaseUrl = "http://127.0.0.1:5010/api"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageDirectory = Join-Path $RepoRoot "deploy\windows-native\agents"
$Packages = @(
    "sr_generation_agent.zip",
    "ar_generation_agent.zip"
)

function Invoke-NexentApi {
    param(
        [ValidateSet("Get", "Post")]
        [string]$Method,
        [string]$Path,
        $Body = $null
    )

    $uri = "$($ApiBaseUrl.TrimEnd('/'))/$($Path.TrimStart('/'))"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri
    }

    $json = $Body | ConvertTo-Json -Depth 100 -Compress
    return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json; charset=utf-8" -Body $json
}

function Get-ExistingResourceNames {
    $agents = @(Invoke-NexentApi -Method Get -Path "agent/list")
    $skillResponse = Invoke-NexentApi -Method Get -Path "skills"

    return [pscustomobject]@{
        AgentNames = @($agents | ForEach-Object { $_.name })
        SkillNames = @($skillResponse.skills | ForEach-Object { $_.name })
    }
}

function Import-AgentPackage {
    param(
        [string]$PackagePath,
        [string[]]$ExistingAgentNames,
        [string[]]$ExistingSkillNames
    )

    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("nexent-agent-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($PackagePath, $temporaryDirectory)
        $agentJsonPath = Join-Path $temporaryDirectory "agent.json"
        if (-not (Test-Path -LiteralPath $agentJsonPath)) {
            throw "agent.json is missing from $PackagePath"
        }

        $agentData = Get-Content -LiteralPath $agentJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $rootAgentKey = [string]$agentData.agent_id
        $rootAgentProperty = $agentData.agent_info.PSObject.Properties[$rootAgentKey]
        if ($null -eq $rootAgentProperty) {
            throw "Root agent $rootAgentKey is missing from $PackagePath"
        }

        $rootAgent = $rootAgentProperty.Value
        if ($ExistingAgentNames -contains $rootAgent.name) {
            Write-Host "  SKIP $($rootAgent.display_name): already installed" -ForegroundColor Yellow
            return
        }

        # Model IDs are database-local. Resolve by display name on Windows,
        # with the configured quick LLM as the backend's final fallback.
        foreach ($agentProperty in $agentData.agent_info.PSObject.Properties) {
            $agentProperty.Value.model_ids = @()
            $agentProperty.Value.business_logic_model_id = $null
        }

        $skillEntries = @()
        $skillResolutions = @()
        $skillsDirectory = Join-Path $temporaryDirectory "skills"
        if (Test-Path -LiteralPath $skillsDirectory) {
            foreach ($skillArchive in Get-ChildItem -LiteralPath $skillsDirectory -Filter "*.zip") {
                $skillName = [System.IO.Path]::GetFileNameWithoutExtension($skillArchive.Name)
                $skillEntries += @{
                    skill_name = $skillName
                    skill_zip_base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($skillArchive.FullName))
                }
                if ($ExistingSkillNames -contains $skillName) {
                    $skillResolutions += @{
                        skill_name = $skillName
                        action = "use_existing"
                    }
                }
            }
        }

        $importPayload = @{
            agent_info = $agentData
            force_import = $false
            skills = $skillEntries
            skill_resolutions = $skillResolutions
        }
        $importResult = Invoke-NexentApi -Method Post -Path "agent/import" -Body $importPayload
        $newAgentId = [int]$importResult.agent_id
        if ($newAgentId -le 0) {
            throw "Nexent did not return a valid agent_id for $($rootAgent.name)"
        }

        # Import creates V1 before Skill instances are attached. Publish again
        # so the runnable version contains the bundled Skill.
        $publishPayload = @{
            version_name = "Windows bundled Skill"
            release_note = "Imported from the windows_dev bundled document agents."
        }
        $null = Invoke-NexentApi -Method Post -Path "agent/$newAgentId/publish" -Body $publishPayload
        $currentVersion = Invoke-NexentApi -Method Get -Path "agent/$newAgentId/current_version"
        $versionDetail = Invoke-NexentApi -Method Get -Path "agent/$newAgentId/versions/$($currentVersion.version_no)/detail"

        if ($currentVersion.status -ne "RELEASED" -or @($versionDetail.skills).Count -eq 0) {
            throw "Agent $($rootAgent.name) was imported, but its released version does not contain a Skill"
        }

        Write-Host "  OK $($rootAgent.display_name): agent_id=$newAgentId, version=$($currentVersion.version_no)" -ForegroundColor Green
    }
    finally {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $PackageDirectory)) {
    throw "Bundled agent directory not found: $PackageDirectory"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

try {
    $null = Invoke-NexentApi -Method Get -Path "agent/list"
}
catch {
    throw "Nexent Config service is not available at $ApiBaseUrl. Start Nexent first. $($_.Exception.Message)"
}

Write-Host "Installing bundled SR/AR document agents" -ForegroundColor Cyan
foreach ($packageName in $Packages) {
    $packagePath = Join-Path $PackageDirectory $packageName
    if (-not (Test-Path -LiteralPath $packagePath)) {
        throw "Bundled agent package not found: $packagePath"
    }

    $existing = Get-ExistingResourceNames
    Import-AgentPackage -PackagePath $packagePath `
        -ExistingAgentNames $existing.AgentNames `
        -ExistingSkillNames $existing.SkillNames
}

Write-Host "Document agents are ready. Open http://localhost:3000/zh/agents" -ForegroundColor Green
