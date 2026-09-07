# Windows 原生部署（不使用 Docker 或 WSL）

该方式直接在 Windows 上运行 Nexent 应用进程，适合本地开发和功能测试。它默认使用 `speed` 模式，
因此不启动 Supabase，也不显示登录页面。

## 默认启动范围

默认启动以下服务：

- Config：端口 `5010`
- Runtime：端口 `5014`
- MCP 与管理接口：端口 `5011`、`5015`
- Data Process（文档解析、分片、向量化）：端口 `5012`
- Web：端口 `3000`

如果只测试对话和智能体配置，可使用 `-WithoutDataProcess` 跳过较重的文档处理依赖；对外北向 API 使用
`-IncludeNorthbound`。

## Windows 本机依赖

- Windows 10/11 x64、PowerShell 5.1 或更高版本
- Python 3.11、`uv`
- Node.js 20 或更高版本、`pnpm`
- PostgreSQL：`127.0.0.1:5432`
- Redis 兼容服务：`127.0.0.1:6379`，Windows 可使用 Memurai
- Elasticsearch：`127.0.0.1:9200`
- MinIO：`127.0.0.1:9000`
- PostgreSQL 角色 `root` 和数据库 `nexent`

本地 Elasticsearch 可以在 `elasticsearch.yml` 设置 `xpack.security.enabled: false`。首次运行后，可以在
`.nexent-windows/.env` 修改所有服务地址和凭据。

创建开发数据库：

```powershell
$env:PGPASSWORD = "<PostgreSQL 管理员密码>"
psql -U postgres -d postgres -c "CREATE ROLE root WITH LOGIN SUPERUSER PASSWORD 'nexent@4321';"
createdb -U postgres -O root nexent
Remove-Item Env:PGPASSWORD
```

如果角色或数据库已经存在，不要重复创建，直接执行部署脚本即可。

## 使用方法

先检查依赖：

```powershell
.\deploy-windows-native.ps1 -Action Doctor
```

安装应用依赖、初始化数据库、构建前端并启动 Nexent：

```powershell
.\deploy-windows-native.ps1
```

管理服务：

```powershell
.\deploy-windows-native.ps1 -Action Status
.\deploy-windows-native.ps1 -Action Stop
.\deploy-windows-native.ps1 -Action Restart
```

## 安装 SR/AR 文档智能体

仓库已内置 `SR生成智能体` 和 `AR生成智能体`，并分别捆绑 `sr-generation`、`ar-generation` Skill。
Nexent 启动并完成大模型配置后，在仓库根目录执行：

```powershell
.\install-document-agents-windows.ps1
```

脚本会按名称跳过已经安装的智能体，复用已有同名 Skill，并在导入后发布一个包含 Skill 的可运行版本。
导出的模型 ID 不会跨数据库复用；脚本优先按显示名称匹配 Windows 已配置模型，匹配不到时使用快速配置中的 LLM。
脚本不会写入或提交 API Key。

不需要文档处理，或需要外部 API 时：

```powershell
.\deploy-windows-native.ps1 -WithoutDataProcess
.\deploy-windows-native.ps1 -IncludeNorthbound
```

也可以双击或在 CMD 中使用：

```bat
deploy-windows-native.cmd -Action Doctor
deploy-windows-native.cmd
```

运行数据、日志、环境配置和 PID 记录统一存放在 `.nexent-windows/`，不会提交到 Git。

## 限制

- 这是本地测试模式，不是生产部署方案。
- 不包含完整模式的登录、用户和租户隔离。
- Skill 脚本使用 `local` 沙箱，没有容器隔离，只能在可信机器运行可信 Skill。
- Ray 和部分文档解析库在 Windows 上的兼容性弱于 Linux；若安装或启动失败，可先使用 `-WithoutDataProcess`
  测试其余功能。
- 不使用 Docker 不代表不需要基础服务；PostgreSQL、Redis、Elasticsearch 和 MinIO 仍然必须运行。
