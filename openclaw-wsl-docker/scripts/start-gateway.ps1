#Requires -Version 5.1
<#
.SYNOPSIS
    OpenClaw Gateway Windows 启动/监控脚本
.DESCRIPTION
    提供 Gateway 的启动、停止、状态检查、自动重启功能
    注意: 必须使用 PowerShell 运行, 不要使用 .bat 批处理
    (Windows 路径含括号如 "Program Files (x86)" 会导致 CMD 批处理脚本报错)
.PARAMETER Action
    操作: Start | Stop | Status | Restart
.EXAMPLE
    .\start-gateway.ps1 -Action Start
    .\start-gateway.ps1 -Action Status
#>

param(
    [ValidateSet("Start", "Stop", "Status", "Restart")]
    [string]$Action = "Start"
)

# ============================================================
# 配置区 - 按实际环境修改
# ============================================================
$CONFIG = @{
    # OpenClaw 入口文件路径 (源码构建产物或全局安装路径)
    # 如果用 npm 全局安装, 设为 "openclaw" 即可
    EntryPoint    = "openclaw"
    # 如果是源码构建, 改为如:
    # EntryPoint  = "node"
    # EntryArgs   = @("<DRIVE>:\openclaw\dist\openclaw.mjs")

    # Gateway 参数
    Port          = 18789
    Bind          = "loopback"

    # 额外 CLI 参数
    ExtraArgs     = @("--allow-unconfigured")

    # 配置文件路径 (留空使用默认 ~/.openclaw/openclaw.json)
    ConfigPath    = ""

    # 日志目录
    LogDir        = "$env:USERPROFILE\.openclaw\logs"

    # 自动重启
    AutoRestart   = $true
    RestartDelay  = 5       # 秒
    MaxRestarts   = 10      # 最大连续重启次数
}

# ============================================================
# 函数定义
# ============================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    if (Test-Path $CONFIG.LogDir) {
        $logFile = Join-Path $CONFIG.LogDir "gateway-$(Get-Date -Format 'yyyyMMdd').log"
        $line | Out-File -Append -FilePath $logFile -Encoding utf8
    }
}

function Get-GatewayProcess {
    Get-Process -Name "node" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*openclaw*" -or $_.CommandLine -like "*gateway*" }
}

function Test-GatewayHealth {
    try {
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:$($CONFIG.Port)/health" -TimeoutSec 3
        return $true
    } catch {
        return $false
    }
}

function Start-Gateway {
    # 检查是否已在运行
    $existing = Get-GatewayProcess
    if ($existing) {
        Write-Log "Gateway 已在运行 (PID: $($existing.Id -join ', '))" "WARN"
        return
    }

    # 创建日志目录
    if (-not (Test-Path $CONFIG.LogDir)) {
        New-Item -ItemType Directory -Path $CONFIG.LogDir -Force | Out-Null
    }

    # 构建启动命令
    $args = @("gateway", "run", "--bind", $CONFIG.Bind, "--port", $CONFIG.Port)
    $args += $CONFIG.ExtraArgs

    # 设置环境变量
    if ($CONFIG.ConfigPath) {
        $env:OPENCLAW_CONFIG_PATH = $CONFIG.ConfigPath
    }

    Write-Log "启动 Gateway: $($CONFIG.EntryPoint) $($args -join ' ')"

    $restartCount = 0

    do {
        try {
            if ($CONFIG.EntryPoint -eq "node") {
                # 源码构建模式
                $allArgs = $CONFIG.EntryArgs + $args
                $process = Start-Process -FilePath "node" -ArgumentList $allArgs `
                    -NoNewWindow -PassThru -RedirectStandardError (Join-Path $CONFIG.LogDir "gateway-error.log")
            } else {
                # 全局安装模式
                $process = Start-Process -FilePath $CONFIG.EntryPoint -ArgumentList $args `
                    -NoNewWindow -PassThru -RedirectStandardError (Join-Path $CONFIG.LogDir "gateway-error.log")
            }

            Write-Log "Gateway 已启动 (PID: $($process.Id))"

            # 等待启动完成
            Start-Sleep -Seconds 3

            if (Test-GatewayHealth) {
                Write-Log "Gateway 健康检查通过 ✓"
                $restartCount = 0
            } else {
                Write-Log "Gateway 健康检查未通过, 可能仍在初始化" "WARN"
            }

            # 等待进程退出
            $process.WaitForExit()
            $exitCode = $process.ExitCode
            Write-Log "Gateway 进程退出, 退出码: $exitCode" "WARN"

        } catch {
            Write-Log "启动异常: $($_.Exception.Message)" "ERROR"
        }

        $restartCount++

        if ($CONFIG.AutoRestart -and $restartCount -le $CONFIG.MaxRestarts) {
            Write-Log "将在 $($CONFIG.RestartDelay) 秒后重启 (第 $restartCount 次)..."
            Start-Sleep -Seconds $CONFIG.RestartDelay
        }

    } while ($CONFIG.AutoRestart -and $restartCount -le $CONFIG.MaxRestarts)

    if ($restartCount -gt $CONFIG.MaxRestarts) {
        Write-Log "达到最大重启次数 ($($CONFIG.MaxRestarts)), 停止自动重启" "ERROR"
    }
}

function Stop-Gateway {
    $processes = Get-GatewayProcess
    if (-not $processes) {
        Write-Log "没有运行中的 Gateway 进程"
        return
    }
    foreach ($proc in $processes) {
        Write-Log "停止进程 PID: $($proc.Id)"
        Stop-Process -Id $proc.Id -Force
    }
    Write-Log "Gateway 已停止"
}

function Show-Status {
    $processes = Get-GatewayProcess
    $healthy = Test-GatewayHealth
    $portUsed = Get-NetTCPConnection -LocalPort $CONFIG.Port -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "=== OpenClaw Gateway 状态 ===" -ForegroundColor Cyan
    Write-Host "进程运行: $(if ($processes) { '✓ PID ' + ($processes.Id -join ', ') } else { '✗ 未运行' })"
    Write-Host "端口监听: $(if ($portUsed) { '✓ :' + $CONFIG.Port } else { '✗ 未监听' })"
    Write-Host "健康检查: $(if ($healthy) { '✓ 正常' } else { '✗ 异常' })"
    Write-Host "配置文件: $(if ($CONFIG.ConfigPath) { $CONFIG.ConfigPath } else { '~/.openclaw/openclaw.json (默认)' })"
    Write-Host ""
}

# ============================================================
# 主逻辑
# ============================================================
switch ($Action) {
    "Start"   { Start-Gateway }
    "Stop"    { Stop-Gateway }
    "Status"  { Show-Status }
    "Restart" { Stop-Gateway; Start-Sleep -Seconds 2; Start-Gateway }
}
