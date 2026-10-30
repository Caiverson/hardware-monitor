# ============================================================
# Windows Hardware Monitor - 一键部署脚本
# 用法：右键“以管理员身份运行 PowerShell”，执行：
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\install.ps1
# 可选参数：
#   .\install.ps1 -ExternalPort 10095 -InternalPort 19092
# ============================================================
param(
    [int]$ExternalPort = 10095,
    [int]$InternalPort = 19092,
    [string]$ContainerName = "monitor-proxy",
    [string]$TaskName = "HardwareMonitor"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step($msg) { Write-Host "`n[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[!] $msg" -ForegroundColor Yellow }

# ---------- 1. 检查管理员权限 ----------
Write-Step "检查管理员权限"
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "部署需要管理员权限（用于创建计划任务读取硬件传感器）。" -ForegroundColor Red
    Write-Host "请右键 PowerShell 选择“以管理员身份运行”后重新执行本脚本。" -ForegroundColor Red
    exit 1
}
Write-Ok "管理员权限确认"

# ---------- 2. 检查文件完整性 ----------
Write-Step "检查项目文件"
$required = @("admin-monitor.ps1", "charts.html", "data.html", "echarts.min.js", "monitor-nginx.conf")
foreach ($f in $required) {
    if (-not (Test-Path (Join-Path $scriptDir $f))) {
        Write-Host "缺少核心文件: $f" -ForegroundColor Red
        exit 1
    }
}
if (-not (Test-Path (Join-Path $scriptDir "LibreHardwareMonitor\LibreHardwareMonitorLib.dll"))) {
    Write-Host "缺少 LibreHardwareMonitorLib.dll" -ForegroundColor Red
    exit 1
}
Write-Ok "文件完整"

# ---------- 3. 检查 Docker ----------
Write-Step "检查 Docker 环境"
$dockerOk = $false
try {
    $null = docker version --format '{{.Server.Version}}' 2>$null
    if ($LASTEXITCODE -eq 0) { $dockerOk = $true }
} catch {}
if (-not $dockerOk) {
    Write-Host "Docker 未安装或未运行。请先安装并启动 Docker Desktop。" -ForegroundColor Red
    Write-Host "下载地址: https://www.docker.com/products/docker-desktop/" -ForegroundColor Yellow
    exit 1
}
Write-Ok "Docker 运行中"

# ---------- 4. 同步内部端口配置 ----------
Write-Step "同步端口配置（内部端口 $InternalPort）"
# 替换 admin-monitor.ps1 中的端口
$monitorPath = Join-Path $scriptDir "admin-monitor.ps1"
$monitorContent = Get-Content $monitorPath -Raw
$monitorContent = [regex]::Replace($monitorContent, '\$port\s*=\s*\d+', "`$port = $InternalPort")
[System.IO.File]::WriteAllText($monitorPath, $monitorContent, (New-Object System.Text.UTF8Encoding($false)))

# 生成运行时 nginx 配置（替换内部端口）
$nginxTemplate = Get-Content (Join-Path $scriptDir "monitor-nginx.conf") -Raw
$nginxRuntime = $nginxTemplate -replace 'host\.docker\.internal:\d+', "host.docker.internal:$InternalPort" -replace 'localhost:\d+', "localhost:$InternalPort"
$runtimeConf = Join-Path $scriptDir ".runtime-nginx.conf"
[System.IO.File]::WriteAllText($runtimeConf, $nginxRuntime, (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "端口配置已同步"

# ---------- 5. 创建/更新 Nginx 容器 ----------
Write-Step "配置 Nginx 反向代理容器"
$existing = docker ps -a --filter "name=^${ContainerName}$" --format "{{.Names}}"
if ($existing) {
    Write-Warn2 "发现旧容器，删除后重建"
    docker rm -f $ContainerName | Out-Null
}
$mount = "$($runtimeConf):/etc/nginx/conf.d/default.conf:ro"
docker run -d --name $ContainerName --restart always -p "${ExternalPort}:80" -v $mount nginx:alpine | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "容器创建失败，请检查外部端口 $ExternalPort 是否被占用。" -ForegroundColor Red
    exit 1
}
Write-Ok "容器已启动（外部端口 $ExternalPort）"

# ---------- 6. 创建/更新计划任务 ----------
Write-Step "配置开机自启计划任务（最高权限）"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$monitorPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
Write-Ok "计划任务已创建"

# ---------- 7. 启动并验证 ----------
Write-Step "启动监控服务"
# 清理可能占用内部端口的旧任务实例
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Start-ScheduledTask -TaskName $TaskName

Write-Host "等待服务初始化（含硬件预热，约 20 秒）..."
$ready = $false
for ($i = 0; $i -lt 12; $i++) {
    Start-Sleep -Seconds 3
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:$InternalPort/api/data" -UseBasicParsing -TimeoutSec 4
        if ($resp.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
}
if (-not $ready) {
    Write-Host "服务启动超时，请检查计划任务状态：Get-ScheduledTask -TaskName $TaskName" -ForegroundColor Red
    exit 1
}
Write-Ok "监控服务运行正常"

# ---------- 8. 输出结果 ----------
$lanIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host " 部署完成！" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  本机访问 : http://localhost:$ExternalPort/charts.html"
Write-Host "  局域网   : http://$lanIp`:$ExternalPort/charts.html"
Write-Host "  数据页   : http://localhost:$ExternalPort/data.html"
Write-Host "------------------------------------------------------------"
Write-Host "  公网访问 : 需在路由器映射 TCP $ExternalPort 到本机"
Write-Host "  计划任务 : $TaskName（开机自动以管理员权限启动）"
Write-Host "  卸载方法 : 以管理员运行 .\uninstall.ps1"
Write-Host "============================================================`n" -ForegroundColor Green
