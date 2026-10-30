# ============================================================
# Windows Hardware Monitor - 卸载脚本
# 用法：以管理员身份运行 .\uninstall.ps1
# ============================================================
param(
    [string]$ContainerName = "monitor-proxy",
    [string]$TaskName = "HardwareMonitor"
)
$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "请以管理员身份运行本脚本。" -ForegroundColor Red
    exit 1
}

Write-Host "[*] 停止并删除计划任务..." -ForegroundColor Cyan
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "[OK] 计划任务已删除" -ForegroundColor Green

Write-Host "[*] 删除 Nginx 容器..." -ForegroundColor Cyan
docker rm -f $ContainerName 2>$null | Out-Null
Write-Host "[OK] 容器已删除（镜像 nginx:alpine 保留，如需删除请手动执行 docker rmi nginx:alpine）" -ForegroundColor Green

$runtime = Join-Path $scriptDir ".runtime-nginx.conf"
if (Test-Path $runtime) { Remove-Item $runtime -Force }

Write-Host "`n[完成] 硬件监控已卸载，项目文件保留在原目录。" -ForegroundColor Green
