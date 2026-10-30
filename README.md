# Windows Hardware Monitor

Windows 主机硬件实时监控网页，支持本机、局域网与手机公网访问，实时查看 CPU、GPU、主板、内存、硬盘的温度、负载、频率、功耗、风扇转速。

基于 **LibreHardwareMonitor + PowerShell + ECharts + Docker Nginx**，提供一键部署脚本与 AI 部署 Skill。

## 特性

- 0.5 秒自动刷新，ECharts 专业图表（仪表盘 + 折线图 + 双 Y 轴）
- 两个页面：图表页 `charts.html`、纯数据页 `data.html`
- 本地 ECharts，不依赖外部 CDN
- Docker Nginx 反向代理，容器化公网入口
- 管理员计划任务，开机自动运行，无需手动点 UAC
- 一键安装 / 卸载，附带 AI 部署 `SKILL.md`

## 快速开始

### 环境要求

- Windows 10/11
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) 已安装并运行
- 以**管理员身份**打开 PowerShell

### 一键部署

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1
```

自定义端口（可选）：

```powershell
.\install.ps1 -ExternalPort 10095 -InternalPort 19092
```

部署完成后访问：

- 本机：http://localhost:10095/charts.html
- 局域网：http://本机IP:10095/charts.html
- 公网：在路由器映射 TCP 10095 到本机后，通过公网 IP/域名访问

### 卸载

```powershell
.\uninstall.ps1
```

## 目录结构

```
hardware-monitor/
├── install.ps1              # 一键部署（管理员）
├── uninstall.ps1            # 一键卸载
├── SKILL.md                 # AI 大模型部署 Skill
├── admin-monitor.ps1        # 监控后端（LibreHardwareMonitor + HttpListener）
├── charts.html              # 图表页
├── data.html                # 纯数据页
├── echarts.min.js           # ECharts 本地库
├── monitor-nginx.conf       # Nginx 配置模板
├── LibreHardwareMonitor/    # 硬件监控库（含 LibreHardwareMonitorLib.dll）
└── docs/
    └── 开发文档.md           # 架构、排查、还原详细文档
```

## 架构

```
浏览器 → 路由器(10095) → Docker Nginx(10095:80)
      → PowerShell 监控服务(localhost:19092)
      → LibreHardwareMonitorLib → 硬件传感器
```

## 用 AI 大模型部署

本项目包含标准 `SKILL.md`。支持读取 Skill 的 AI 助手可直接依据该文件完成环境检查、部署、验证与故障排查。

## 文档

- 详细开发与还原文档：[docs/开发文档.md](docs/开发文档.md)
- AI 部署指引：[SKILL.md](SKILL.md)

## 免责声明

仅用于个人硬件监控与学习用途，不构成任何专业建议。LibreHardwareMonitor 为开源软件，遵循其对应许可证。
