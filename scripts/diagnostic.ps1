# Comprehensive Diagnostic Script for Telemetry Stack
# Перевіряє всі компоненти системи

param(
    [switch]$Detailed,
    [switch]$Export
)

$ErrorActionPreference = "Continue"

# Кольори для виводу
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Логування результатів
$LogFile = "C:\TelemetryStack\logs\diagnostic_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogDir = Split-Path $LogFile -Parent

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force
}

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $LogFile -Value $logMessage
}

Write-ColorOutput "=== Telemetry Stack Diagnostic ===" "Green"
Write-Log "Starting diagnostic check"

# 1. Системна інформація
Write-ColorOutput "`n1. System Information:" "Yellow"
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
Write-ColorOutput "OS: $($osInfo.Caption) $($osInfo.Version)" "White"
Write-ColorOutput "Architecture: $($osInfo.OSArchitecture)" "White"
Write-ColorOutput "Total RAM: $([math]::Round($osInfo.TotalVisibleMemorySize/1MB, 2)) GB" "White"

$cpuInfo = Get-WmiObject -Class Win32_Processor
Write-ColorOutput "CPU: $($cpuInfo.Name)" "White"
Write-ColorOutput "CPU Cores: $($cpuInfo.NumberOfCores)" "White"

# 2. Docker інформація
Write-ColorOutput "`n2. Docker Information:" "Yellow"
try {
    $dockerVersion = docker --version
    Write-ColorOutput "✅ Docker: $dockerVersion" "Green"
    Write-Log "Docker version: $dockerVersion"
} catch {
    Write-ColorOutput "❌ Docker not found or not running" "Red"
    Write-Log "Docker not found"
}

try {
    $composeVersion = docker compose version
    Write-ColorOutput "✅ Docker Compose: $composeVersion" "Green"
    Write-Log "Docker Compose version: $composeVersion"
} catch {
    Write-ColorOutput "❌ Docker Compose not found" "Red"
    Write-Log "Docker Compose not found"
}

# 3. Перевірка контейнерів
Write-ColorOutput "`n3. Container Status:" "Yellow"
try {
    $containers = docker compose -f docker-compose.local.yml ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    Write-ColorOutput $containers "White"
    Write-Log "Container status: $containers"
} catch {
    Write-ColorOutput "❌ Failed to get container status" "Red"
    Write-Log "Failed to get container status"
}

# 4. Перевірка здоров'я сервісів
Write-ColorOutput "`n4. Health Checks:" "Yellow"
$services = @("timescaledb", "grafana", "telegraf", "pgadmin", "redis")
$healthyCount = 0

foreach ($service in $services) {
    try {
        $health = docker inspect "${service}_1" --format "{{.State.Health.Status}}" 2>$null
        if ($health -eq "healthy") {
            Write-ColorOutput "✅ $service`: $health" "Green"
            $healthyCount++
        } elseif ($health -eq "unhealthy") {
            Write-ColorOutput "❌ $service`: $health" "Red"
        } else {
            Write-ColorOutput "⚠️  $service`: $health" "Yellow"
        }
        Write-Log "$service health: $health"
    } catch {
        Write-ColorOutput "❌ $service`: Failed to check health" "Red"
        Write-Log "$service health check failed"
    }
}

Write-ColorOutput "Healthy services: $healthyCount/$($services.Count)" "Blue"

# 5. Перевірка ресурсів
Write-ColorOutput "`n5. Resource Usage:" "Yellow"
try {
    $stats = docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
    Write-ColorOutput $stats "White"
    Write-Log "Resource usage: $stats"
} catch {
    Write-ColorOutput "❌ Failed to get resource usage" "Red"
    Write-Log "Failed to get resource usage"
}

# 6. Перевірка мережі
Write-ColorOutput "`n6. Network Status:" "Yellow"
try {
    $networks = docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
    Write-ColorOutput $networks "White"
    Write-Log "Networks: $networks"
} catch {
    Write-ColorOutput "❌ Failed to get network info" "Red"
    Write-Log "Failed to get network info"
}

# 7. Перевірка доступності сервісів
Write-ColorOutput "`n7. Service Accessibility:" "Yellow"

# Grafana
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -TimeoutSec 5 -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-ColorOutput "✅ Grafana: Accessible (HTTP $($response.StatusCode))" "Green"
        Write-Log "Grafana accessible: HTTP $($response.StatusCode)"
    }
} catch {
    Write-ColorOutput "❌ Grafana: Not accessible - $($_.Exception.Message)" "Red"
    Write-Log "Grafana not accessible: $($_.Exception.Message)"
}

# TimescaleDB
try {
    $result = docker exec timescaledb pg_isready -U postgres -d telemetry 2>$null
    if ($result -match "accepting connections") {
        Write-ColorOutput "✅ TimescaleDB: Accepting connections" "Green"
        Write-Log "TimescaleDB accepting connections"
    } else {
        Write-ColorOutput "❌ TimescaleDB: Not accepting connections" "Red"
        Write-Log "TimescaleDB not accepting connections"
    }
} catch {
    Write-ColorOutput "❌ TimescaleDB: Connection failed" "Red"
    Write-Log "TimescaleDB connection failed"
}

# pgAdmin
try {
    $response = Invoke-WebRequest -Uri "http://localhost:5050/misc/ping" -TimeoutSec 5 -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-ColorOutput "✅ pgAdmin: Accessible (HTTP $($response.StatusCode))" "Green"
        Write-Log "pgAdmin accessible: HTTP $($response.StatusCode)"
    }
} catch {
    Write-ColorOutput "❌ pgAdmin: Not accessible - $($_.Exception.Message)" "Red"
    Write-Log "pgAdmin not accessible: $($_.Exception.Message)"
}

# 8. Перевірка розміру даних
Write-ColorOutput "`n8. Data Size:" "Yellow"
try {
    $timescaleSize = (Get-ChildItem ".\timescaledb\data" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $grafanaSize = (Get-ChildItem ".\grafana\data" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $pgadminSize = (Get-ChildItem ".\pgadmin" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    
    Write-ColorOutput "TimescaleDB: $([math]::Round($timescaleSize/1GB,2)) GB" "Blue"
    Write-ColorOutput "Grafana: $([math]::Round($grafanaSize/1GB,2)) GB" "Blue"
    Write-ColorOutput "pgAdmin: $([math]::Round($pgadminSize/1GB,2)) GB" "Blue"
    
    $totalSize = $timescaleSize + $grafanaSize + $pgadminSize
    Write-ColorOutput "Total: $([math]::Round($totalSize/1GB,2)) GB" "Blue"
    
    Write-Log "Data sizes - TimescaleDB: $([math]::Round($timescaleSize/1GB,2)) GB, Grafana: $([math]::Round($grafanaSize/1GB,2)) GB, Total: $([math]::Round($totalSize/1GB,2)) GB"
} catch {
    Write-ColorOutput "❌ Failed to calculate data sizes" "Red"
    Write-Log "Failed to calculate data sizes"
}

# 9. Перевірка логів на помилки
Write-ColorOutput "`n9. Recent Errors:" "Yellow"
try {
    $recentErrors = docker compose -f docker-compose.local.yml logs --tail=50 | Select-String -Pattern "error|Error|ERROR|fatal|Fatal|FATAL|exception|Exception" | Select-Object -Last 10
    if ($recentErrors) {
        Write-ColorOutput "Recent errors found:" "Red"
        $recentErrors | ForEach-Object { Write-ColorOutput "  $($_.Line)" "Red" }
        Write-Log "Recent errors: $($recentErrors -join '; ')"
    } else {
        Write-ColorOutput "✅ No recent errors found" "Green"
        Write-Log "No recent errors found"
    }
} catch {
    Write-ColorOutput "❌ Failed to check logs" "Red"
    Write-Log "Failed to check logs"
}

# 10. Перевірка конфігурацій
Write-ColorOutput "`n10. Configuration Check:" "Yellow"

# Перевірка .env файлу
if (Test-Path ".env") {
    Write-ColorOutput "✅ .env file exists" "Green"
    Write-Log ".env file exists"
} else {
    Write-ColorOutput "❌ .env file missing" "Red"
    Write-Log ".env file missing"
}

# Перевірка docker-compose файлу
if (Test-Path "docker-compose.local.yml") {
    Write-ColorOutput "✅ docker-compose.local.yml exists" "Green"
    Write-Log "docker-compose.local.yml exists"
} else {
    Write-ColorOutput "❌ docker-compose.local.yml missing" "Red"
    Write-Log "docker-compose.local.yml missing"
}

# Перевірка Telegraf конфігурації
if (Test-Path "telegraf\telegraf.conf") {
    Write-ColorOutput "✅ telegraf.conf exists" "Green"
    Write-Log "telegraf.conf exists"
} else {
    Write-ColorOutput "❌ telegraf.conf missing" "Red"
    Write-Log "telegraf.conf missing"
}

# 11. Рекомендації
Write-ColorOutput "`n11. Recommendations:" "Yellow"

if ($healthyCount -lt $services.Count) {
    Write-ColorOutput "⚠️  Some services are not healthy. Check logs:" "Yellow"
    Write-ColorOutput "   docker compose -f docker-compose.local.yml logs" "White"
}

if ($totalSize -gt 10GB) {
    Write-ColorOutput "⚠️  Large data size detected. Consider:" "Yellow"
    Write-ColorOutput "   - Implementing data retention policies" "White"
    Write-ColorOutput "   - Regular backups" "White"
    Write-ColorOutput "   - Data archiving" "White"
}

# 12. Експорт результатів
if ($Export) {
    $exportFile = "C:\TelemetryStack\logs\diagnostic_export_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $exportContent = @"
Telemetry Stack Diagnostic Report
Generated: $(Get-Date)
System: $($osInfo.Caption) $($osInfo.Version)
Docker: $dockerVersion
Healthy Services: $healthyCount/$($services.Count)
Total Data Size: $([math]::Round($totalSize/1GB,2)) GB
"@
    
    $exportContent | Out-File -FilePath $exportFile -Encoding UTF8
    Write-ColorOutput "📄 Diagnostic report exported to: $exportFile" "Blue"
    Write-Log "Diagnostic report exported to: $exportFile"
}

Write-ColorOutput "`n=== Diagnostic Complete ===" "Green"
Write-ColorOutput "Log file: $LogFile" "Blue"
Write-Log "Diagnostic completed"
