---
name: openclaw-wsl-docker
description: "Comprehensive skill for OpenClaw AI Gateway deployment, configuration, and troubleshooting across Windows and WSL2 environments. Use when: deploying OpenClaw on Windows; fixing config validation errors (OpenClaw Zod strict mode); building from source when npm packages are incomplete; troubleshooting Telegram bot integration failures in WSL2; installing and hardening OpenClaw Admin UI; diagnosing polling stalls, 403/409 errors, or proxy timeouts in Telegram channels; configuring WSL networking (mirrored/NAT)."
---

# OpenClaw AI Gateway — 全环境部署与运维技能

> **融合技能**：将 OpenClaw 在 Windows 部署、配置修复、源码构建、Telegram 集成故障排查、Admin UI 安装加固五大场景整合为一套标准流程。

---

## 目录

1. [概述与适用范围](#1-概述与适用范围)
2. [环境总览](#2-环境总览)
3. [Windows 部署 OpenClaw Gateway](#3-windows-部署-openclaw-gateway)
4. [配置校验与修复](#4-配置校验与修复)
5. [源码构建](#5-源码构建)
6. [Telegram 集成故障排查](#6-telegram-集成故障排查)
7. [OpenClaw Admin UI](#7-openclaw-admin-ui)
8. [速查表与附录](#8-速查表与附录)

---

## 1. 概述与适用范围

### 1.1 适用场景

| 场景 | 触发条件 | 参考章节 |
|------|---------|---------|
| Windows 首次安装 Gateway | 用户希望从零开始安装 OpenClaw | §3 |
| 配置文件校验失败 | Gateway 拒绝启动，报 `Unrecognized keys` | §4 |
| npm 包不完整 | `Cannot find module`, `dist/` 缺失 | §5 |
| Telegram 消息收不到 | 长轮询卡死、403/409 错误、超时 | §6 |
| 部署 Admin UI | 需要可视化管理面板 | §8 |

### 1.2 什么是 OpenClaw

OpenClaw 是一个开源的 AI 代理网关，支持多模型路由、代理编排、Telegram/Web Chat 等渠道集成。其配置文件使用 **JSON5 格式**（支持注释和尾逗号），配置路径默认为 `~/.openclaw/openclaw.json`。

### 1.3 核心原则

- **严格模式校验**：OpenClaw 使用 Zod 进行配置校验，任何 Schema 中未定义的键会导致 Gateway 拒绝启动
- **Windows 专用 PowerShell**：避免使用 `.bat` 批处理（路径含括号会导致崩溃）
- **网络分层诊断**：WSL → Windows → 代理 → Telegram API，逐层排查
- **先修复配置，再变更运行时**

### 1.4 部署前置自检

在启动 Gateway 前，先执行一轮最小可验证检查，降低“配置错误 → 服务不可用”的延迟：

```powershell
$PSVersionTable.PSVersion.ToString()
Get-Command node -ErrorAction SilentlyContinue
Get-Command openclaw -ErrorAction SilentlyContinue
Test-Path "$env:USERPROFILE\.openclaw"
```

- 若 `Get-Command openclaw` 为空，先执行 `npm install -g openclaw@latest` 或切换为源码模式。
- 若配置目录不存在，先创建 `~/.openclaw/` 并准备 `openclaw.json`。
- 若 `gateway.mode` 未配置，先启用 `--allow-unconfigured` 或在配置中显式设置 `mode: "local"`。

---

## 2. 环境总览

### 2.1 软件依赖

| 组件 | 最低版本 | 安装方式 |
|------|---------|---------|
| Node.js | v22.0+ | `winget install OpenJS.NodeJS.LTS` |
| pnpm | v8+ | `npm install -g pnpm` |
| Git | 任意 | `winget install Git.Git` |
| Python3 | ≥ 3.10 | 按需（node-pty 编译时） |

### 2.2 端口规划

| 端口 | 用途 |
|------|------|
| 18789 | Gateway 主端口（WebSocket + HTTP） |
| 3001 | Admin UI（可选） |
| 8082 | 浏览器控制服务（独立端口） |

### 2.3 目录结构

```
~/.openclaw/                    # 用户配置目录
├── openclaw.json               # 主配置文件 (JSON5)
├── .env                        # 环境变量文件
├── logs/                       # 日志目录
│   └── config-audit.jsonl      # 配置变更审计日志
├── workspace/                  # 代理工作区
├── agents/                     # 代理定义
│   └── main/agent/
├── services/                   # 辅助服务
│   └── admin-ui/               # Admin UI 运行时目录
└── external/                   # 外部源码镜像
    └── src-mirrors/
```

---

## 3. Windows 部署 OpenClaw Gateway

### 3.1 安装方式

#### 方式 A：npm 全局安装（推荐优先尝试）

```powershell
npm install -g openclaw@latest
openclaw --version
openclaw doctor --fix
```

#### 方式 B：一键安装（PowerShell）

```powershell
irm https://get.openclaw.ai | iex
openclaw onboard --install-daemon
```

#### 方式 C：源码构建（npm 包不完整时使用，见 §5）

### 3.2 启动 Gateway

```powershell
# 全局安装后直接启动
openclaw gateway run

# 指定参数启动
openclaw gateway run --bind loopback --port 18789

# 首次启动需要 --allow-unconfigured（或配置 gateway.mode）
openclaw gateway run --bind loopback --port 18789 --allow-unconfigured

# 指定配置文件路径
$env:OPENCLAW_CONFIG_PATH = "$env:USERPROFILE\.openclaw\openclaw.json"
openclaw gateway run
```

### 3.3 启动验证

```powershell
# 检查端口监听
Get-NetTCPConnection -LocalPort 18789 -ErrorAction SilentlyContinue

# 健康检查
Invoke-RestMethod -Uri "http://127.0.0.1:18789/health"

# 查看状态
openclaw gateway status
```

### 3.4 PowerShell 启动脚本

参见本技能目录下的 `scripts/start-gateway.ps1`，提供 Start / Stop / Status / Restart 四个操作。

### 3.5 安全加固

#### Windows 防火墙规则

```powershell
# 仅允许本地访问 Gateway 端口
New-NetFirewallRule -DisplayName "OpenClaw Loopback Only" `
    -Direction Inbound -Protocol TCP -LocalPort 18789 `
    -RemoteAddress "127.0.0.1" -Action Allow
```

#### 文件权限

```powershell
# 限制 .env 和 openclaw.json 的访问权限
icacls "$env:USERPROFILE\.openclaw\.env" /inheritance:r /grant "$env:USERNAME:(R)"
icacls "$env:USERPROFILE\.openclaw\openclaw.json" /inheritance:r /grant "$env:USERNAME:(R)"
```

### 3.6 Windows 特有注意事项

| 问题 | 说明 | 解决方案 |
|------|------|---------|
| 路径含括号 | `Program Files (x86)` 导致 .bat 脚本崩溃 | 只使用 PowerShell |
| npm 包缺少 dist | `Cannot find module './internal/core'` | 切换至源码构建 |
| 端口占用 | `Get-NetTCPConnection -LocalPort 18789` 查占用 | `Stop-Process -Id <PID> -Force` |
| PowerShell 执行策略 | 脚本被阻止运行 | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| 首次启动被阻止 | `gateway.mode` 未设置 | 配置 `mode: "local"` 或加 `--allow-unconfigured` |
| Auth Token 自动生成 | 首次启动自动生成并写入配置 | 建议预先在配置中设置 |
| Control UI 构建失败 | 缺少 pnpm 导致（非致命） | `npm install -g pnpm` 后重启 |
| Browser Control 独立端口 | 默认端口 8082 | 注意审查端口暴露 |

---

## 4. 配置校验与修复

### 4.1 核心原则

OpenClaw 使用 **Zod 严格模式**校验配置文件。任何未在 Schema 中定义的键都会导致 Gateway 拒绝启动并报错。

### 4.2 常见错误模式

#### 模式 1：Unrecognized keys（顶层未知键）

```
Invalid config at ~/.openclaw/openclaw.json
  <root>: Unrecognized keys: "security", "performance"
```

**原因**：顶层出现了 Schema 中不存在的节
**修复**：删除这些键。合法顶层键见下方列表。

#### 模式 2：gateway.bind Invalid input

```
gateway.bind: Invalid input
```

**原因**：`bind` 值写了 IP 地址（如 `"127.0.0.1"`）
**修复**：改为 `"loopback"`（仅本地）或 `"lan"`（局域网）

#### 模式 3：Unrecognized key in nested object

```
gateway.auth: Unrecognized key: "enabled"
logging: Unrecognized keys: "format", "maxSize", "maxFiles", "auditLog"
```

**原因**：嵌套对象中使用了不存在的键
**修复**：按合法键列表修正

#### 模式 4：Gateway 启动被阻止（mode 未设置）

```
Gateway start blocked: set gateway.mode=local (current: unset) or pass --allow-unconfigured.
```

**原因**：`gateway.mode` 未在配置中设置
**修复**（二选一）：
1. 配置文件中添加 `gateway: { mode: "local" }`
2. 启动时加 `--allow-unconfigured`

#### 模式 5：JSON5 语法错误

```
SyntaxError: Unexpected token
```

**原因**：JSON 格式错误
**修复**：检查括号配对、逗号、引号

### 4.3 合法配置 Schema 速查

#### 合法顶层键

```
agents  bindings  browser  canvasHost
channels  commands  cron  discovery
env  gateway  hooks  logging
messages  models  plugins  secrets
session  skills  talk  tools
ui  wizard  auth
```

> ❌ **不存在的顶层键**：`security`, `performance`, `server`, `backup`, `monitoring`, `sandbox`

#### gateway 合法键

```json5
gateway: {
  mode,           // "local" | "remote"
  port,           // number
  bind,           // "loopback" | "lan" | "auto" | "tailnet" | "custom"
  auth: {
    mode,         // "none" | "token" | "password" | "trusted-proxy"
    token,        // string
    password,     // string
    allowTailscale, // boolean
    rateLimit: {
      maxAttempts,   // number
      windowMs,      // number
      lockoutMs,     // number
      exemptLoopback, // boolean
    },
  },
  controlUi: { enabled, basePath },
  tailscale: { mode, resetOnExit },
  remote: { url, transport, token, password },
  trustedProxies, // string[]
  tools: { allow, deny },
  http: { endpoints: { chatCompletions: { enabled }, responses: { enabled } } },
}
```

#### logging 合法键

```json5
logging: {
  level,            // "debug" | "info" | "warn" | "error"
  file,             // string (文件路径)
  consoleLevel,     // "debug" | "info" | "warn" | "error"
  consoleStyle,     // "pretty" | "compact" | "json"
  redactSensitive,  // "off" | "tools"
  redactPatterns,   // string[] (正则数组)
}
// ❌ 不存在: format, maxSize, maxFiles, auditLog
```

#### agents 合法键

```json5
agents: {
  defaults: {
    workspace, repoRoot, skipBootstrap, bootstrapMaxChars,
    bootstrapTotalMaxChars, imageMaxDimensionPx, userTimezone,
    timeFormat, model, imageModel, models,
    thinkingDefault, timeoutSeconds, maxConcurrent,
    heartbeat, compaction, contextPruning, sandbox,
    subagents, blockStreamingDefault, typingMode,
  },
  list: [{
    id, default, name, workspace,
    model, params, identity,
    groupChat, sandbox, tools,
  }],
}
```

#### tools 合法键

```json5
tools: {
  profile,        // "minimal" | "coding" | "messaging" | "full"
  allow, deny, byProvider,
  elevated, exec, loopDetection,
  web, media, sessions,
  agentToAgent, subagents, sandbox,
}
```

#### session 合法键

```json5
session: {
  scope, dmScope, identityLinks,
  reset, resetTriggers, store,
  maintenance, threadBindings,
  agentToAgent, sendPolicy,
}
```

### 4.4 常见错误 → 正确写法对照

| 错误写法 | 正确写法 |
|----------|---------|
| `gateway: { bind: "127.0.0.1" }` | `gateway: { bind: "loopback" }` |
| `gateway: { auth: { enabled: true } }` | `gateway: { auth: { mode: "token" } }` |
| `logging: { format: "json" }` | `logging: { consoleStyle: "json" }` |
| `logging: { maxSize: "10m" }` | ❌ 删除，logging 无此键 |
| `security: { ... }` / `performance: { ... }` | ❌ 删除，顶层无此键 |
| `server: { port: 3000 }` | `gateway: { port: 18789 }` |
| `sandbox: { mode: "off" }`（顶层） | `agents: { defaults: { sandbox: { mode: "off" } } }` |

### 4.5 自动修复命令

```powershell
# OpenClaw 内置诊断修复（推荐首选）
openclaw doctor --fix

# 手动验证配置
openclaw config get gateway
openclaw config get logging
```

### 4.6 最小可用配置模板

```json5
// ~/.openclaw/openclaw.json
{
  gateway: {
    port: 18789,
    bind: "loopback",
  },
}
```

### 4.7 安全加固配置模板

```json5
{
  gateway: {
    mode: "local",
    port: 18789,
    bind: "loopback",
    auth: {
      mode: "token",
      token: "${OPENCLAW_GATEWAY_TOKEN}",
      rateLimit: {
        maxAttempts: 10,
        windowMs: 60000,
        lockoutMs: 300000,
        exemptLoopback: true,
      },
    },
    controlUi: {
      enabled: true,
      basePath: "/openclaw",
    },
  },
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: {
        primary: "<provider>/<model>",
        fallbacks: ["<provider>/<model>"],
      },
      timeoutSeconds: 600,
    },
    list: [{ id: "main", default: true, name: "primary-agent" }],
  },
  tools: {
    profile: "coding",
    exec: { timeoutSec: 1800 },
  },
  logging: {
    level: "info",
    consoleLevel: "info",
    consoleStyle: "pretty",
    redactSensitive: "tools",
  },
}
```

### 4.8 Auth Token 自动生成行为

- 首次启动 Gateway 时，若配置中缺少 auth token，自动生成一个 128 字符随机 token
- 写入 `~/.openclaw/openclaw.json`
- 日志输出：`auth token was missing. Generated a new token and saved it to config`
- 配置变更记录在 `~/.openclaw/logs/config-audit.jsonl`

### 4.9 自定义模型提供商（如 Ollama 本地模型）

```json5
{
  models: {
    mode: "merge",
    providers: {
      "local-ollama": {
        baseUrl: "http://localhost:11434/v1",
        api: "openai-completions",
        models: [
          {
            id: "qwen2.5:7b",
            name: "Qwen 2.5 7B",
            reasoning: false,
            input: ["text"],
            contextWindow: 32768,
            maxTokens: 8192,
          },
        ],
      },
    },
  },
  agents: {
    defaults: {
      model: "local-ollama/qwen2.5:7b",
    },
  },
}
```

---

## 5. 源码构建

### 5.1 何时需要源码构建

**症状**（出现任一即需源码构建）：
- `Cannot find module './internal/core'`
- `dist/openclaw.mjs` 不存在
- `dist/` 目录为空或不存在
- `Get-ChildItem "$npmDir\dist"` 返回空

**诊断命令**：
```powershell
$npmDir = "$env:APPDATA\npm\node_modules\openclaw"
Test-Path "$npmDir\dist\openclaw.mjs"     # False = 需要源码构建
Get-ChildItem "$npmDir\dist" -ErrorAction SilentlyContinue | Measure-Object
```

### 5.2 构建步骤

```powershell
# 1. 确认 Node.js >= 22 和 pnpm
node -v
pnpm -v    # 若无: npm install -g pnpm

# 2. 克隆源码（选择无空格无括号的路径）
$buildDir = "<DRIVE>:\openclaw-build"
git clone https://github.com/openclawai/openclaw.git $buildDir
cd $buildDir

# 3. 安装依赖（必须加 --ignore-scripts，避免不兼容的 postinstall）
pnpm install --ignore-scripts

# 4. 构建
npx tsdown

# 5. 验证构建产物
Test-Path "dist/openclaw.mjs"  # 必须为 True
Get-ChildItem dist/*.mjs | Select-Object Name, Length

# 6. 测试启动
node dist/openclaw.mjs gateway run --bind loopback --port 18789 --allow-unconfigured

# 7. 部署到目标目录（可选）
$targetDir = "<DRIVE>:\openclaw"
New-Item -ItemType Directory -Path $targetDir -Force
Copy-Item -Path "dist\*" -Destination "$targetDir\dist\" -Recurse -Force
Copy-Item -Path "node_modules" -Destination "$targetDir\node_modules" -Recurse -Force
Copy-Item -Path "package.json" -Destination "$targetDir\" -Force
```

### 5.3 路径注意事项

| 路径类型 | 推荐 | 不推荐 |
|---------|------|--------|
| 构建/部署目录 | `<DRIVE>:\openclaw`, `%USERPROFILE%\openclaw` | `C:\Program Files\`（需管理员）、含空格或中文的路径、含括号的路径 |
| 脚本语言 | PowerShell `.ps1`（✅ 正常处理括号和空格） | CMD `.bat`（❌ 路径含括号会崩溃） |

### 5.4 更新流程

```powershell
cd $buildDir
git pull origin main
pnpm install --ignore-scripts
npx tsdown
Copy-Item -Path "dist\*" -Destination "$targetDir\dist\" -Recurse -Force
```

---

## 6. Telegram 集成故障排查

### 6.1 问题分类速查

| 类型 | 症状 | 最常见根因 |
|------|------|-----------|
| **A：长轮询卡死** | 日志中 getUpdates 无新条目（10分钟+），消息不到达 | 代理地址不一致，运行时文件有过期 IP |
| **B：403/404 错误** | `403 Forbidden: bots can't send messages to bots` | chat_id 用了 Bot 的 ID 而非用户 ID |
| **C：连接超时** | `UND_ERR_CONNECT_TIMEOUT` / `Network request failed` | WSL 未正确配置代理或代理未启动 |

### 6.2 关键概念

**三个必须同步的代理位置**：
1. **Windows**：v2rayN/xray 监听地址（通常 `127.0.0.1:10808`）
2. **WSL 环境变量**：`export HTTP_PROXY=http://127.0.0.1:10808`
3. **运行时文件**：`runtime-proxy.env`

> 这三个位置必须一致。从 WSL NAT 模式切到 mirrored 模式后，代理 IP 会从大网段（如 `172.x.x.x`）切到 `127.0.0.1`，所有配置必须同步更新。

**Bot ID vs User ID**：
- Bot ID：通过 `getMe` API 获取，用于识别 Bot 本身
- User ID：从用户发来的消息中提取，用于白名单
- 若 `chat_id` 是 Bot ID，会收到 `403 Forbidden` 错误

### 6.3 诊断决策树

```
用户报告：Gateway 启动了，但 Telegram 消息收不到
│
├─ Step 1: Gateway 进程存活？
│  └─ pgrep -a openclaw | grep gateway
│     ├─ 找不到 → 重启 Gateway
│     └─ 找到 → 继续
│
├─ Step 2: Telegram provider 已启动？
│  └─ grep "starting provider" /tmp/openclaw/openclaw-*.log
│     ├─ 看不到 → 检查 Telegram channel.enabled
│     └─ 看到 → 继续
│
├─ Step 3: 长轮询连接是否活跃？
│  └─ cat /proc/[gateway-pid]/net/tcp | grep ESTABLISHED
│     ├─ 无连接 → 检查代理配置
│     └─ 有指向代理的连接 → 继续
│
├─ Step 4: 代理环境变量正确？
│  └─ cat /proc/[gateway-pid]/environ | tr '\0' '\n' | grep -i proxy
│     ├─ 不正确 → 更新启动脚本
│     └─ 正确 → 继续
│
├─ Step 5: 代理本身能工作？
│  └─ 用 Python 测试代理可访问 Telegram API
│     ├─ 超时 → 启动/修复代理
│     └─ 成功 → 继续
│
├─ Step 6: 白名单配置正确？
│  └─ 确认 groupAllowFrom 包含真实用户 ID（非 Bot ID）
│     ├─ 包含 Bot ID → 用 getUpdates 获取用户 ID 并修正
│     └─ 正确 → 继续
│
├─ Step 7: 有消息错误？
│  └─ grep -i "chat=\|sendMessage\|send failed" /tmp/openclaw/openclaw-*.log
│     ├─ 403 → chat_id 问题（参考 Step 6）
│     ├─ 409 → 有重复轮询，重启 Gateway
│     └─ 成功 → 正常
│
└─ 问题解决！
```

### 6.4 常用诊断命令

| 诊断项 | 命令 |
|--------|------|
| Gateway 存活 | `pgrep -a openclaw` |
| Telegram 模块启用 | `grep "starting provider" /tmp/openclaw/openclaw-*.log \| tail -1` |
| TCP 连接状态 | `cat /proc/[pid]/net/tcp \| grep ESTABLISHED` |
| 代理环境变量 | `cat /proc/[pid]/environ \| tr '\0' '\n' \| grep -i proxy` |
| 最近错误 | `grep -i "error\|failed\|timeout" /tmp/openclaw/openclaw-*.log \| tail -20` |
| 最近消息 | `grep "chat=" /tmp/openclaw/openclaw-*.log \| tail -10` |
| Bot ID | 通过 `getMe` API 获取 |
| 用户 ID | 通过 `getUpdates` 从消息中提取 |

### 6.5 常见修复场景

#### 场景 1：代理地址从 WSL NAT 切到 mirrored 模式

```ini
# C:\Users\<用户名>\.wslconfig
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
localhostForwarding=true
```

```powershell
wsl --shutdown
wsl -d Ubuntu
```

```bash
# WSL 内更新运行时代理文件
# ~/.openclaw/runtime-proxy.env
HTTPS_PROXY=http://127.0.0.1:10808
HTTP_PROXY=http://127.0.0.1:10808
NO_PROXY=127.0.0.1,localhost,::1
```

#### 场景 2：白名单中混了 Bot ID

```bash
# 获取 Bot 自己的 ID
TOKEN=$(sed -n 's/^OPENCLAW_TELEGRAM_TOKEN=//p' /path/to/.env)
python3 -c "
import urllib.request, json
r = urllib.request.urlopen(f'https://api.telegram.org/bot{TOKEN}/getMe')
print('Bot ID:', json.loads(r.read())['result']['id'])
"

# 获取真实用户 ID（用户需先向 Bot 发消息）
python3 -c "
import urllib.request, json
r = urllib.request.urlopen(f'https://api.telegram.org/bot{TOKEN}/getUpdates?limit=1', timeout=5)
data = json.loads(r.read())
for u in data.get('result', []):
    msg = u.get('message', {})
    print('User ID:', msg.get('from', {}).get('id'))
    print('Chat ID:', msg.get('chat', {}).get('id'))
"

# 更新白名单
sed -i 's/"groupAllowFrom": \["<BOT_ID>"\]/"groupAllowFrom": ["<USER_ID>"]/' /path/to/openclaw.json
```

#### 场景 3：长轮询卡死，需强制重启 Gateway

```bash
# 创建启动脚本
cat > /tmp/gw_start.sh << 'EOF'
#!/bin/bash
export HTTP_PROXY=http://127.0.0.1:10808
export HTTPS_PROXY=http://127.0.0.1:10808
export NO_PROXY=127.0.0.1,localhost,::1
exec openclaw gateway --port 18789
EOF
chmod +x /tmp/gw_start.sh

# 后台启动（不会因 shell 退出而杀死）
wsl -d Ubuntu -e bash /tmp/gw_start.sh &
```

### 6.6 预防性检查清单

每次部署或配置变更后运行：

- [ ] `.wslconfig` 中 `networkingMode=mirrored` 且 `autoProxy=true`
- [ ] 运行时代理文件中代理 IP 是 `127.0.0.1`（而非旧 NAT IP）
- [ ] `openclaw.json` 中 `groupAllowFrom` 包含真实用户 ID
- [ ] 启动脚本包含 `export HTTP_PROXY=...` 且不会因 shell 退出而杀进程
- [ ] 测试代理可用性（Python 脚本或 curl）
- [ ] 发送一条测试消息，验证 Gateway 能收到
- [ ] 监控 30 秒，确认 Telegram 长轮询仍有活动

### 6.7 错误消息对照表

| 错误消息 | 解读 | 修复方向 |
|---------|------|---------|
| `UND_ERR_CONNECT_TIMEOUT` | 无法连接到 Telegram API | 检查代理配置或网络连接 |
| `403 Forbidden: bots can't send messages to bots` | chat_id 是 Bot 自己的 ID | 用用户 ID 替换 Bot ID |
| `409 Conflict: getUpdates` | 两个轮询同时进行 | 只保留一个 Gateway 实例 |
| `Polling stall detected` | 轮询连接卡死 > 120 秒 | 重启 Gateway，检查代理 |
| `Network request for 'getUpdates' failed` | 代理断线或超时 | 检查 HTTP_PROXY 环境变量 |

---

## 7. OpenClaw Admin UI

### 7.1 环境要求

| 依赖 | 最低版本 | 说明 |
|------|---------|------|
| Node.js | ≥ 18.0.0 | v22 LTS 推荐 |
| npm | ≥ 9.0.0 | |
| Python3 | ≥ 3.10 | node-gyp 编译 node-pty 时需要 |
| build-essential | 任意 | `apt install build-essential` |
| OpenClaw Gateway | 已运行 | 默认 Gateway 端口 18789 |

**WSL2 注意**：在 mirrored 网络模式下，Admin UI 应绑定到 `127.0.0.1` 而非 `0.0.0.0`。

### 7.2 安装流程

```bash
# 1. 克隆源码
mkdir -p ~/.openclaw/external/src-mirrors
cd ~/.openclaw/external/src-mirrors
git clone https://github.com/itq5/OpenClaw-Admin.git openclaw-admin

# 2. 准备运行时目录
mkdir -p ~/.openclaw/services/admin-ui/{server,data,logs,backups,archive,public}
cp -r ~/.openclaw/external/src-mirrors/openclaw-admin/server \
      ~/.openclaw/services/admin-ui/
cd ~/.openclaw/services/admin-ui
npm install

# 3. 配置 .env
cat > ~/.openclaw/services/admin-ui/.env << 'EOF'
PORT=3001
HOST=127.0.0.1
AUTH_USERNAME=admin
AUTH_PASSWORD=<strong_password>
OPENCLAW_GATEWAY_URL=http://127.0.0.1:18789
OPENCLAW_GATEWAY_TOKEN=<gateway_token>
SESSION_SECRET=<random_32_char_secret>
NODE_ENV=production
EOF
chmod 600 ~/.openclaw/services/admin-ui/.env

# 4. 构建前端
cd ~/.openclaw/external/src-mirrors/openclaw-admin
npm install
npm run build
cp -r dist ~/.openclaw/services/admin-ui/
rm -rf node_modules  # 可选：节省磁盘空间
```

### 7.3 systemd 服务配置

```ini
# /etc/systemd/system/openclaw-admin.service
[Unit]
Description=OpenClaw Admin UI
After=network.target openclaw.service
Wants=openclaw.service

[Service]
Type=simple
User=root
WorkingDirectory=/root/.openclaw/services/admin-ui
ExecStart=/usr/bin/node server/index.js
Restart=always
RestartSec=5
EnvironmentFile=/root/.openclaw/services/admin-ui/.env
StandardOutput=append:/root/.openclaw/services/admin-ui/logs/admin-ui.log
StandardError=append:/root/.openclaw/services/admin-ui/logs/admin-ui-error.log

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now openclaw-admin
```

### 7.4 安全加固

> Admin UI 上游项目存在多个高风险区域，生产环境使用前需应用以下加固。

**1. 路径遍历防护**
```javascript
const safePath = path.resolve(allowedBaseDir, userInput);
if (!safePath.startsWith(allowedBaseDir)) {
  return res.status(403).json({ error: "Path traversal detected" });
}
```

**2. 禁用远程终端和桌面路由**
```javascript
// 注释或移除以下路由注册
// app.ws('/api/terminal', ...)        // node-pty WebSocket
// app.get('/api/remote-desktop', ...) // RemoteDesktop
// app.get('/api/myworld', ...)        // MyWorld
```

**3. RPC 方法白名单**
```javascript
const ALLOWED_RPC_METHODS = new Set([
  "agents.list", "agents.update", "agents.create", "agents.delete",
  "config.get", "config.patch", "config.set", "config.apply",
  "models.list", "sessions.list", "sessions.get", "sessions.reset",
  "cron.list", "cron.add", "cron.update", "cron.delete", "cron.run",
  "memory.list", "memory.get", "memory.update",
]);
// 在 /api/rpc 路由中检查：
if (!ALLOWED_RPC_METHODS.has(method)) {
  return res.status(400).json({ error: `Blocked method: ${method}` });
}
```

**4. 安全响应头**
```javascript
app.use((req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("X-XSS-Protection", "1; mode=block");
  res.setHeader("Referrer-Policy", "no-referrer");
  next();
});
```

**5. 禁用 index.html 缓存**
```javascript
res.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
res.setHeader("Pragma", "no-cache");
```

**6. Gateway 自动重启**
```ini
# 在 /etc/systemd/system/openclaw.service 的 [Service] 节添加
Restart=always
RestartSec=5
RestartPreventExitStatus=2
```

### 7.5 补充后端端点

#### /api/provider/test — 测试提供商连通性

```javascript
app.post("/api/provider/test", authMiddleware, async (req, res) => {
  const { baseUrl, apiKey, api } = req.body;
  if (!baseUrl || !apiKey) return res.status(400).json({ ok: false });
  const testUrl = baseUrl.replace(/\/+$/, "") + "/models";
  try {
    const response = await fetch(testUrl, {
      headers: { Authorization: `Bearer ${apiKey}` },
      signal: AbortSignal.timeout(15000),
    });
    const data = await response.json();
    const models = data.data || data.models || [];
    res.json({ ok: response.ok, status: response.status, modelCount: models.length });
  } catch (err) {
    res.status(200).json({ ok: false, error: { message: err.message } });
  }
});
```

#### /api/provider/models — 获取远程模型列表

```javascript
app.post("/api/provider/models", authMiddleware, async (req, res) => {
  const { baseUrl, apiKey } = req.body;
  const response = await fetch(baseUrl.replace(/\/+$/, "") + "/models", {
    headers: { Authorization: `Bearer ${apiKey}` },
    signal: AbortSignal.timeout(20000),
  });
  const data = await response.json();
  const models = (data.data || data.models || []).map((m) => ({
    id: m.id,
    name: m.id,
    context_length: m.context_length,
  }));
  res.json({ ok: true, models });
});
```

#### /api/config/backup — Apply 前创建配置快照

```javascript
// 注意: server/index.js 使用 ES modules (import/export)，不要使用 require()
app.post("/api/config/backup", authMiddleware, async (req, res) => {
  try {
    const configPath = join(
      process.env.OPENCLAW_HOME || "/root/.openclaw",
      "openclaw.json",
    );
    const timestamp = new Date()
      .toISOString()
      .replace(/[:.]/g, "-")
      .slice(0, 19);
    const backupPath = configPath + ".pre-apply." + timestamp;
    copyFileSync(configPath, backupPath);
    res.json({ ok: true, backupPath, size: statSync(backupPath).size });
  } catch (err) {
    res.status(500).json({ ok: false, error: { message: err.message } });
  }
});
```

### 7.6 前端修复要点

- Apply 按钮应始终可见（用 `:disabled` 而非 `v-if` 控制状态）
- 模型选择器应从 RPC `models.list` 结果构建，而非从旧配置结构读取

---

## 8. 速查表与附录

### 8.1 速查表

| 场景 | 关键命令 |
|------|---------|
| 安装 Gateway | `npm install -g openclaw@latest` |
| 启动 Gateway | `openclaw gateway run --bind loopback --port 18789` |
| 健康检查 | `Invoke-RestMethod -Uri "http://127.0.0.1:18789/health"` |
| 诊断配置 | `openclaw doctor --fix` |
| 查看配置 | `openclaw config get gateway` |
| 查看状态 | `openclaw gateway status` |
| 查找端口占用 | `Get-NetTCPConnection -LocalPort 18789` |
| 停止进程 | `Stop-Process -Id <PID> -Force` |
| 源码诊断 | `Test-Path "$env:APPDATA\npm\node_modules\openclaw\dist\openclaw.mjs"` |
| 检查 Telegram TCP | `cat /proc/[pid]/net/tcp \| grep ESTABLISHED` |
| 检查代理变量 | `cat /proc/[pid]/environ \| tr '\0' '\n' \| grep -i proxy` |
| WSL 重启 | `wsl --shutdown` |

### 8.2 诊断数据收集步骤

当问题无法快速解决时，按以下顺序收集信息：

1. **环境版本**：`node -v`, `pnpm -v`, `openclaw --version`
2. **Gateway 状态**：`openclaw gateway status`, 健康检查
3. **配置内容**：`openclaw config get gateway`
4. **日志摘录**：最近 50 行错误日志（`grep -i error`）
5. **网络拓扑**：确认代理服务是否运行、端口是否可达
6. **进程检查**：确认无重复 Gateway 实例

### 8.3 使用本技能的最佳实践

1. **首次部署** → 按 §3（安装）→ §4（配置）顺序执行
2. **配置报错** → 直接跳到 §4，用合法键对照表修正
3. **Telegram 不通** → 按 §6 决策树逐层排查
4. **npm 包不完整** → 跳到 §5 源码构建
5. **Admin UI 部署** → 跳到 §7，并务必应用安全加固

### 8.4 脱敏说明

> 本技能文件已对以下内容进行脱敏处理：真实用户名、路径、API Token、Bot Token、Chat ID、用户 ID、IP 地址、域名。示例中的占位符如 `<provider>/<model>`、`<strong_password>`、`<gateway_token>`、`<USER_ID>`、`<BOT_ID>` 等需替换为实际值。
