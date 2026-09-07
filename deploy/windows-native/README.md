# Native Windows deployment (without Docker or WSL)

This deployment path runs Nexent application processes directly on Windows. It is intended for local development and
functional testing. It uses speed mode, so Supabase login and tenant isolation are disabled.

## Scope

The default process set is `config`, `runtime`, `mcp`, `data-process`, and `web`, including document ingestion and
vectorization. Use `-WithoutDataProcess` for a lighter chat/configuration-only installation, or `-IncludeNorthbound` for
external APIs. Skill scripts use the local sandbox; keep this mode on a trusted development machine only.

## Native prerequisites

- Windows 10/11 x64 with PowerShell 5.1 or later
- Python 3.11, `uv`, Node.js 20 or later, and `pnpm`
- PostgreSQL on `127.0.0.1:5432`
- A Redis-compatible Windows service on `127.0.0.1:6379` (for example, Memurai)
- Elasticsearch on `127.0.0.1:9200`
- MinIO on `127.0.0.1:9000`
- A PostgreSQL role named `root` and database named `nexent`

For local Elasticsearch without authentication, set `xpack.security.enabled: false`. The values can be changed in
`.nexent-windows/.env` after its first creation.

Create the development database with PostgreSQL tools:

```powershell
$env:PGPASSWORD = "<postgres-admin-password>"
psql -U postgres -d postgres -c "CREATE ROLE root WITH LOGIN SUPERUSER PASSWORD 'nexent@4321';"
createdb -U postgres -O root nexent
Remove-Item Env:PGPASSWORD
```

## Commands

Run the prerequisite check:

```powershell
.\deploy-windows-native.ps1 -Action Doctor
```

Install dependencies, initialize the schema, build the frontend, and start Nexent:

```powershell
.\deploy-windows-native.ps1
```

Manage the native processes:

```powershell
.\deploy-windows-native.ps1 -Action Status
.\deploy-windows-native.ps1 -Action Stop
.\deploy-windows-native.ps1 -Action Restart
```

## Install the SR/AR document agents

This branch bundles the `SR Generation Agent` and `AR Generation Agent` with
their `sr-generation` and `ar-generation` Skills. After Nexent is running and
an LLM is configured, run this command from the repository root:

```powershell
.\install-document-agents-windows.ps1
```

The installer is idempotent by agent name, reuses an existing same-name Skill,
and publishes a runnable version after attaching the Skill. Exported database
model IDs are discarded; the target model is resolved by display name or falls
back to the Windows quick-config LLM. No API key is stored in the repository.

Disable document processing or enable the optional external API:

```powershell
.\deploy-windows-native.ps1 -WithoutDataProcess
.\deploy-windows-native.ps1 -IncludeNorthbound
```

The CMD wrapper is available for terminals where script execution is restricted:

```bat
deploy-windows-native.cmd -Action Doctor
deploy-windows-native.cmd
```

Runtime files, logs, the generated environment file, and process records live in `.nexent-windows/` and are not committed.

## Limitations

- This is not a production deployment profile.
- Full-mode authentication and Supabase are not included.
- The local Skill sandbox does not provide container isolation.
- Windows support for Ray and some document parsing libraries is less complete than Linux. If installation or startup
  fails, use `-WithoutDataProcess` while testing the remaining features.
- PostgreSQL, Redis, Elasticsearch, and MinIO remain required services even though Docker is not used.
