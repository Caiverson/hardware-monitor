---
name: windows-hardware-monitor-deploy
description: 在 Windows 主机上一键部署「硬件信息监控网页」。当用户要求部署/安装/还原 Windows 硬件监控、PC 状态网页、CPU/GPU 温度监控、LibreHardwareMonitor Web 面板，或需要排查该监控服务时使用。覆盖环境检查、Docker 反向代理、管理员计划任务、自启配置、验证与卸载。
---

# Windows 硬件监控网页部署 Skill

## 1. 这个项目是什么

一个 Windows 原生的硬件实时监控网页，通过浏览器（含手机公网）查看 CPU、GPU、主板、内存、硬盘的温度、负载、频率、功耗、风扇转速。

- 数据采集：LibreHardwareMonitor（开源，读取 Windows 硬件传感器）
- 后端：PowerShell + HttpListener，默认内部端口 19092（仅 localhost）
- 入口：Docker Nginx 反向代理，默认外部端口 10095
- 前端：ECharts 5.5 本地库，0.5 秒刷新，含图表页 charts.html 与数据页 data.html
- 自启：Windows 计划任务，RunLevel Highest（管理员），登录时自动运行

## 2. 触发条件

满足任一即按本 Skill 执行：
- 部署/安装/还原 Windows 硬件监控网页、PC 监控面板
- 提到 LibreHardwareMonitor + Web/网页/手机访问
- 排查该监控的 CPU 温度为 0、页面不更新、容器/计划任务故障
- 用户要求卸载该监控

## 3. 前置条件（先核查，不满足先解决）

1. Windows 10/11，当前 PowerShell 为**管理员身份**
   - 判定：
     ```powershell
     ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
     ```
   - 非管理员：停止操作，提示用户用管理员 PowerShell，不要尝试绕过。
2. Docker Desktop 已安装且正在运行
   - 判定：`docker version --format '{{.Server.Version}}'`
3. 项目文件完整（与 install.ps1 同目录）：
   - admin-monitor.ps1、charts.html、data.html、echarts.min.js、monitor-nginx.conf
   - LibreHardwareMonitor\LibreHardwareMonitorLib.dll
4. 外部端口（默认 10095）未被占用：
   ```powershell
   Get-NetTCPConnection -LocalPort 10095 -ErrorAction SilentlyContinue
   ```

## 4. 标准部署流程（优先用一键脚本）

### 推荐方式：执行 install.ps1

在项目根目录的管理员 PowerShell 中：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1
```

自定义端口（可选）：

```powershell
.\install.ps1 -ExternalPort 10095 -InternalPort 19092
```

脚本会按顺序完成：
1. 校验管理员权限与文件完整性
2. 校验 Docker 运行状态
3. 将内部端口同步进 admin-monitor.ps1，生成无 BOM 的 `.runtime-nginx.conf`
4. 删除旧容器并创建 Nginx 容器（`--restart always`，端口 外部:80，挂载运行时配置）
5. 删除旧计划任务并创建最高权限任务（登录触发、失败自动重启、无执行时限）
6. 启动任务，轮询 `http://localhost:内部端口/api/data` 直到返回 200
7. 输出本机/局域网访问地址与公网映射提示

### 仅当脚本不可用时才手动执行

按 install.ps1 内部同等步骤手工完成，每步验证后再进入下一步；不要自创路径或更换组件版本。

## 5. 验收标准（必须全部满足）

1. 容器状态：
   ```powershell
   docker ps --filter "name=monitor-proxy" --format "{{.Names}} {{.Status}}"
   ```
2. 计划任务状态为 Running：
   ```powershell
   Get-ScheduledTask -TaskName HardwareMonitor
   ```
3. API 返回 200 且为 JSON 数组：
   ```powershell
   (Invoke-WebRequest http://localhost:19092/api/data -UseBasicParsing).StatusCode
   ```
4. 关键数据非 0（管理员权限下）：
   - CPU：`CPU Package` 温度、`CPU Package` 功耗、`CPU Total` 负载
   - GPU：类型为 `GpuAmd`（不是 Gpu），核心温度、显存占用率
5. 外部入口可打开图表页：`http://localhost:10095/charts.html`
6. 页面包含独立仪表盘说明标签（gauge-label）与双 Y 轴（yAxisIndex）

## 6. 关键事实与口径（避免误判）

- 显存占用率**不是** Load 类型的 `GPU Memory`（该值常为 0）。正确口径：
  `SmallData: GPU Memory Used / SmallData: GPU Memory Total × 100`
- AMD 显卡硬件类型是 `GpuAmd`；NVIDIA 通常为 `GpuNvidia`，需按实际类型适配。
- 负载+频率图必须双 Y 轴：左轴负载 0–100%，右轴频率 MHz；颜色：负载蓝、频率绿。
- Nginx 配置必须**无 BOM 的 UTF-8**，否则报 `unknown directive`。
- 容器访问后端必须带 `Host: localhost:内部端口`，否则 HttpListener 返回 400。
- 普通权限下 CPU 温度/功耗/主板传感器读不到，属预期，不是硬件故障。

## 7. 故障排查表

| 现象 | 根因 | 处理 |
|---|---|---|
| CPU 温度/功耗为 0 | 非管理员运行 | 确认由最高权限计划任务启动，重启任务 |
| 改了页面不生效 | 旧 monitor 进程占用端口 | 查所有 powershell 命令行，清理旧进程，URL 加 `?v=数字` |
| Nginx `unknown directive` | 配置含 BOM | 用无 BOM UTF-8 重写，`docker exec monitor-proxy nginx -s reload` |
| 容器返回 400 | Host 头不匹配 | 确认 `proxy_set_header Host localhost:内部端口` |
| 找不到 GPU | 类型判断错误 | 按 `GpuAmd`/`GpuNvidia` 实际类型匹配 |
| 负载线贴 0 轴 | 单 Y 轴 | 改为双 Y 轴并设置 yAxisIndex |
| 显存占用率 0 | 用了失效的 Load 传感器 | 改用 Used/Total 容量计算 |

## 8. 性能影响口径

实测监控整体 CPU 占用通常 <1%，内存约 150 MB（PowerShell 约 138 MB + Nginx 约 12 MB），无磁盘写入、无数据库，数据仅保留内存中最近 30 点，对游戏和日常使用无可感知影响。

## 9. 卸载

管理员 PowerShell 执行：

```powershell
.\uninstall.ps1
```

删除计划任务与 Nginx 容器，保留项目文件；nginx 镜像需手动 `docker rmi nginx:alpine`。

## 10. 维护规则

- 每次修复问题后重新打版本备份，并在 git 提交，提交信息说明修复内容。
- 不要随意升级 LibreHardwareMonitor；升级后必须重新核对传感器名称与前端取数。
- 一次只改一个变量，先验证 localhost 内部服务，再验证外部入口。
