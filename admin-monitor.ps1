# ============================================
# Admin Hardware Monitor
# ============================================
$ErrorActionPreference = "Continue"

# 获取脚本所在目录（支持任意路径部署）
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Loading library..."
Add-Type -Path (Join-Path $scriptDir "LibreHardwareMonitor\LibreHardwareMonitorLib.dll")

$computer = New-Object LibreHardwareMonitor.Hardware.Computer
$computer.IsCpuEnabled = $true
$computer.IsGpuEnabled = $true
$computer.IsMemoryEnabled = $true
$computer.IsMotherboardEnabled = $true
$computer.IsStorageEnabled = $true
$computer.IsNetworkEnabled = $true
$computer.Open()

Write-Host "Hardware count: $($computer.Hardware.Count)"

# Warmup
Write-Host "Warming up..."
for ($round = 0; $round -lt 12; $round++) {
    foreach ($hw in $computer.Hardware) {
        $hw.Update()
        if ($hw.SubHardware) {
            foreach ($sub in $hw.SubHardware) { $sub.Update() }
        }
    }
    Start-Sleep -Milliseconds 400
}

# Check CPU
$cpu = $computer.Hardware | Where-Object { $_.HardwareType.ToString() -eq "Cpu" }
Write-Host "CPU sensors: $($cpu.Sensors.Count)"
Write-Host "CPU Temperature values:"
$cpu.Sensors | Where-Object { $_.SensorType.ToString() -eq "Temperature" } | Select-Object -First 6 | ForEach-Object {
    Write-Host "  $($_.Name) = $($_.Value)"
}

# Read files
$pageData = [System.IO.File]::ReadAllText((Join-Path $scriptDir "data.html"))
$pageCharts = [System.IO.File]::ReadAllText((Join-Path $scriptDir "charts.html"))
$fileEcharts = [System.IO.File]::ReadAllBytes((Join-Path $scriptDir "echarts.min.js"))

# Start listener on port 19092
$port = 19092
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "========================================="
Write-Host "Admin monitor running on port $port"
Write-Host "========================================="

function Get-MonitorData {
    foreach ($hw in $computer.Hardware) {
        $hw.Update()
        if ($hw.SubHardware) {
            foreach ($sub in $hw.SubHardware) { $sub.Update() }
        }
    }
    
    $result = @()
    foreach ($hw in $computer.Hardware) {
        $sensors = @()
        foreach ($sensor in $hw.Sensors) {
            $val = if ($null -ne $sensor.Value) { [math]::Round($sensor.Value, 2) } else { 0 }
            $sensors += [PSCustomObject]@{
                name = $sensor.Name
                type = $sensor.SensorType.ToString()
                value = $val
            }
        }
        if ($hw.SubHardware) {
            foreach ($sub in $hw.SubHardware) {
                foreach ($sensor in $sub.Sensors) {
                    $val = if ($null -ne $sensor.Value) { [math]::Round($sensor.Value, 2) } else { 0 }
                    $sensors += [PSCustomObject]@{
                        name = $sub.Name + " - " + $sensor.Name
                        type = $sensor.SensorType.ToString()
                        value = $val
                    }
                }
            }
        }
        $result += [PSCustomObject]@{
            name = $hw.Name
            type = $hw.HardwareType.ToString()
            sensors = $sensors
        }
    }
    return $result
}

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $path = $context.Request.Url.LocalPath

    if ($path -eq "/api/data") {
        $data = Get-MonitorData
        $json = $data | ConvertTo-Json -Depth 4
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $context.Response.ContentType = "application/json; charset=utf-8"
    }
    elseif ($path -eq "/charts.html") {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($pageCharts)
        $context.Response.ContentType = "text/html; charset=utf-8"
    }
    elseif ($path -eq "/echarts.min.js") {
        $bytes = $fileEcharts
        $context.Response.ContentType = "application/javascript; charset=utf-8"
    }
    else {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($pageData)
        $context.Response.ContentType = "text/html; charset=utf-8"
    }

    $context.Response.ContentLength64 = $bytes.Length
    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $context.Response.OutputStream.Close()
}
