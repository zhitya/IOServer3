# Telegraf Configuration Helper
# Допомагає налаштувати Telegraf для різних сценаріїв

param(
    [string]$Action = "help",
    [string]$DeviceIP = "",
    [int]$DevicePort = 502,
    [int]$SlaveID = 1,
    [string]$DeviceName = "device1"
)

$ErrorActionPreference = "Continue"

function Show-Help {
    Write-Host "Telegraf Configuration Helper" -ForegroundColor Green
    Write-Host "=============================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage: .\telegraf-config-helper.ps1 -Action <action> [options]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Actions:" -ForegroundColor Cyan
    Write-Host "  help              - Show this help"
    Write-Host "  add-modbus        - Add Modbus TCP device"
    Write-Host "  add-network       - Add network monitoring"
    Write-Host "  add-system        - Add system monitoring"
    Write-Host "  test-config       - Test current configuration"
    Write-Host "  backup-config     - Backup current configuration"
    Write-Host "  restore-config    - Restore configuration from backup"
    Write-Host ""
    Write-Host "Options for add-modbus:" -ForegroundColor Cyan
    Write-Host "  -DeviceIP <IP>    - Modbus device IP address"
    Write-Host "  -DevicePort <port> - Modbus device port (default: 502)"
    Write-Host "  -SlaveID <id>     - Modbus slave ID (default: 1)"
    Write-Host "  -DeviceName <name> - Device name for tags"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\telegraf-config-helper.ps1 -Action add-modbus -DeviceIP 192.168.1.100"
    Write-Host "  .\telegraf-config-helper.ps1 -Action add-network"
    Write-Host "  .\telegraf-config-helper.ps1 -Action test-config"
}

function Add-ModbusDevice {
    param($IP, $Port, $SlaveID, $Name)
    
    Write-Host "Adding Modbus TCP device..." -ForegroundColor Green
    Write-Host "IP: $IP" -ForegroundColor Blue
    Write-Host "Port: $Port" -ForegroundColor Blue
    Write-Host "Slave ID: $SlaveID" -ForegroundColor Blue
    Write-Host "Name: $Name" -ForegroundColor Blue
    
    # Створення бекапу поточної конфігурації
    $backupFile = "telegraf\telegraf.conf.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item "telegraf\telegraf.conf" $backupFile
    Write-Host "✅ Configuration backed up to: $backupFile" -ForegroundColor Green
    
    # Читання поточної конфігурації
    $config = Get-Content "telegraf\telegraf.conf" -Raw
    
    # Додавання нового Modbus пристрою
    $newModbusConfig = @"

# Modbus device: $Name
[[inputs.modbus]]
  name = "modbus_$Name"
  controller = "tcp://$IP`:$Port"
  slave_id = $SlaveID
  timeout = "2s"
  retries = 3
  
  [inputs.modbus.tags]
    device_id = "$Name"
    location = "plant_floor"
    protocol = "modbus_tcp"
    ip_address = "$IP"

  # Voltage measurements
  [[inputs.modbus.holding_registers]]
    name = "Voltage_L1"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.1
    address = [0]

  [[inputs.modbus.holding_registers]]
    name = "Voltage_L2"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.1
    address = [1]

  [[inputs.modbus.holding_registers]]
    name = "Voltage_L3"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.1
    address = [2]

  # Current measurements
  [[inputs.modbus.holding_registers]]
    name = "Current_L1"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.01
    address = [10]

  [[inputs.modbus.holding_registers]]
    name = "Current_L2"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.01
    address = [11]

  [[inputs.modbus.holding_registers]]
    name = "Current_L3"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.01
    address = [12]

  # Power measurements (32-bit)
  [[inputs.modbus.holding_registers]]
    name = "Power_Total"
    data_type = "FLOAT32-IEEE"
    byte_order = "ABCD"
    scale = 1.0
    address = [50, 51]

  # Frequency
  [[inputs.modbus.holding_registers]]
    name = "Frequency"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.01
    address = [100]

"@

    # Додавання нової конфігурації
    $config += $newModbusConfig
    
    # Збереження оновленої конфігурації
    $config | Out-File -FilePath "telegraf\telegraf.conf" -Encoding UTF8
    
    Write-Host "✅ Modbus device added to configuration" -ForegroundColor Green
    Write-Host "Configuration saved to: telegraf\telegraf.conf" -ForegroundColor Blue
}

function Add-NetworkMonitoring {
    Write-Host "Adding network monitoring..." -ForegroundColor Green
    
    # Створення бекапу
    $backupFile = "telegraf\telegraf.conf.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item "telegraf\telegraf.conf" $backupFile
    Write-Host "✅ Configuration backed up to: $backupFile" -ForegroundColor Green
    
    # Читання поточної конфігурації
    $config = Get-Content "telegraf\telegraf.conf" -Raw
    
    # Додавання мережевого моніторингу
    $networkConfig = @"

# Network monitoring
[[inputs.ping]]
  urls = ["192.168.1.1", "192.168.1.10", "192.168.1.20", "192.168.1.30"]
  count = 3
  ping_interval = 1.0
  timeout = 3.0
  [inputs.ping.tags]
    network = "production"

[[inputs.net]]
  interfaces = ["eth0", "en0", "Wi-Fi"]
  ignore_protocol_stats = false
  [inputs.net.tags]
    network = "production"

# SNMP monitoring (if SNMP devices available)
# [[inputs.snmp]]
#   agents = ["192.168.1.10:161", "192.168.1.20:161"]
#   community = "public"
#   version = 2
#   [inputs.snmp.tags]
#     network = "production"
#   
#   [[inputs.snmp.field]]
#     name = "hostname"
#     oid = "1.3.6.1.2.1.1.5.0"
#   
#   [[inputs.snmp.field]]
#     name = "uptime"
#     oid = "1.3.6.1.2.1.1.3.0"

"@

    $config += $networkConfig
    $config | Out-File -FilePath "telegraf\telegraf.conf" -Encoding UTF8
    
    Write-Host "✅ Network monitoring added to configuration" -ForegroundColor Green
}

function Add-SystemMonitoring {
    Write-Host "Adding system monitoring..." -ForegroundColor Green
    
    # Створення бекапу
    $backupFile = "telegraf\telegraf.conf.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item "telegraf\telegraf.conf" $backupFile
    Write-Host "✅ Configuration backed up to: $backupFile" -ForegroundColor Green
    
    # Читання поточної конфігурації
    $config = Get-Content "telegraf\telegraf.conf" -Raw
    
    # Додавання системного моніторингу
    $systemConfig = @"

# System monitoring
[[inputs.cpu]]
  percpu = false
  totalcpu = true
  collect_cpu_time = false
  report_active = false
  [inputs.cpu.tags]
    system = "host"

[[inputs.mem]]
  [inputs.mem.tags]
    system = "host"

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]
  [inputs.disk.tags]
    system = "host"

[[inputs.diskio]]
  devices = ["*"]
  name_templates = ["$host/$device"]
  [inputs.diskio.tags]
    system = "host"

[[inputs.processes]]
  [inputs.processes.tags]
    system = "host"

# Windows-specific monitoring
[[inputs.win_perf_counters]]
  [[inputs.win_perf_counters.object]]
    ObjectName = "Processor"
    Instances = ["*"]
    Counters = ["% Processor Time"]
    Measurement = "win_cpu"
    [inputs.win_perf_counters.tags]
      system = "host"

  [[inputs.win_perf_counters.object]]
    ObjectName = "Memory"
    Instances = ["*"]
    Counters = ["Available MBytes", "Committed Bytes"]
    Measurement = "win_mem"
    [inputs.win_perf_counters.tags]
      system = "host"

"@

    $config += $systemConfig
    $config | Out-File -FilePath "telegraf\telegraf.conf" -Encoding UTF8
    
    Write-Host "✅ System monitoring added to configuration" -ForegroundColor Green
}

function Test-Configuration {
    Write-Host "Testing Telegraf configuration..." -ForegroundColor Green
    
    # Перевірка чи Telegraf запущений
    $telegrafStatus = docker inspect telegraf_1 --format "{{.State.Status}}" 2>$null
    if ($telegrafStatus -ne "running") {
        Write-Host "❌ Telegraf is not running" -ForegroundColor Red
        Write-Host "Start Telegraf first: docker compose -f docker-compose.local.yml up -d telegraf" -ForegroundColor Yellow
        return
    }
    
    # Тестування конфігурації
    Write-Host "Running configuration test..." -ForegroundColor Blue
    $testResult = docker exec telegraf telegraf --config /etc/telegraf/telegraf.conf --test 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Configuration test passed" -ForegroundColor Green
        Write-Host "Test output:" -ForegroundColor Blue
        Write-Host $testResult
    } else {
        Write-Host "❌ Configuration test failed" -ForegroundColor Red
        Write-Host "Error output:" -ForegroundColor Red
        Write-Host $testResult
    }
}

function Backup-Configuration {
    $backupFile = "telegraf\telegraf.conf.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item "telegraf\telegraf.conf" $backupFile
    Write-Host "✅ Configuration backed up to: $backupFile" -ForegroundColor Green
}

function Restore-Configuration {
    $backupFiles = Get-ChildItem "telegraf\telegraf.conf.backup.*" | Sort-Object CreationTime -Descending
    
    if ($backupFiles.Count -eq 0) {
        Write-Host "❌ No backup files found" -ForegroundColor Red
        return
    }
    
    Write-Host "Available backups:" -ForegroundColor Blue
    for ($i = 0; $i -lt $backupFiles.Count; $i++) {
        Write-Host "$i`: $($backupFiles[$i].Name) ($($backupFiles[$i].CreationTime))" -ForegroundColor White
    }
    
    $selection = Read-Host "Select backup to restore (0-$($backupFiles.Count-1))"
    
    if ($selection -match "^\d+$" -and [int]$selection -lt $backupFiles.Count) {
        Copy-Item $backupFiles[$selection].FullName "telegraf\telegraf.conf"
        Write-Host "✅ Configuration restored from: $($backupFiles[$selection].Name)" -ForegroundColor Green
    } else {
        Write-Host "❌ Invalid selection" -ForegroundColor Red
    }
}

# Основна логіка
switch ($Action.ToLower()) {
    "help" {
        Show-Help
    }
    "add-modbus" {
        if ([string]::IsNullOrEmpty($DeviceIP)) {
            Write-Host "❌ DeviceIP is required for add-modbus action" -ForegroundColor Red
            Show-Help
        } else {
            Add-ModbusDevice -IP $DeviceIP -Port $DevicePort -SlaveID $SlaveID -Name $DeviceName
        }
    }
    "add-network" {
        Add-NetworkMonitoring
    }
    "add-system" {
        Add-SystemMonitoring
    }
    "test-config" {
        Test-Configuration
    }
    "backup-config" {
        Backup-Configuration
    }
    "restore-config" {
        Restore-Configuration
    }
    default {
        Write-Host "❌ Unknown action: $Action" -ForegroundColor Red
        Show-Help
    }
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Test configuration: .\telegraf-config-helper.ps1 -Action test-config" -ForegroundColor White
Write-Host "2. Restart Telegraf: docker compose -f docker-compose.local.yml restart telegraf" -ForegroundColor White
Write-Host "3. Check logs: docker compose -f docker-compose.local.yml logs telegraf" -ForegroundColor White
