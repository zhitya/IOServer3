# Update Script for Telemetry Stack
# Безпечно оновлює компоненти системи

param(
    [string]$Component = "all",
    [switch]$BackupFirst = $true,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Логування
$LogFile = "C:\TelemetryStack\logs\update.log"
$LogDir = Split-Path $LogFile -Parent

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force
}

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

function Test-ServiceHealthy {
    param($ServiceName)
    try {
        $health = docker inspect "${ServiceName}_1" --format "{{.State.Health.Status}}" 2>$null
        return $health -eq "healthy"
    } catch {
        return $false
    }
}

try {
    Write-Log "Starting Telemetry Stack update process"
    Write-Log "Component to update: $Component"
    
    # Перехід в робочу папку
    Set-Location "C:\TelemetryStack"
    
    # 1. Створення бекапу (якщо потрібно)
    if ($BackupFirst) {
        Write-Log "Creating backup before update..."
        & ".\scripts\backup.ps1" -Compress
        if ($LASTEXITCODE -ne 0) {
            throw "Backup failed, aborting update"
        }
        Write-Log "✅ Backup completed"
    }
    
    # 2. Отримання нових образів
    Write-Log "Pulling latest Docker images..."
    
    if ($Component -eq "all" -or $Component -eq "timescaledb") {
        Write-Log "Updating TimescaleDB image..."
        docker pull timescale/timescaledb:latest-pg16
    }
    
    if ($Component -eq "all" -or $Component -eq "grafana") {
        Write-Log "Updating Grafana image..."
        docker pull grafana/grafana:10.4.4
    }
    
    if ($Component -eq "all" -or $Component -eq "telegraf") {
        Write-Log "Updating Telegraf image..."
        docker pull telegraf:1.30
    }
    
    if ($Component -eq "all" -or $Component -eq "pgadmin") {
        Write-Log "Updating pgAdmin image..."
        docker pull dpage/pgadmin4:8.12
    }
    
    if ($Component -eq "all" -or $Component -eq "redis") {
        Write-Log "Updating Redis image..."
        docker pull redis:7-alpine
    }
    
    Write-Log "✅ Images pulled successfully"
    
    # 3. Зупинка сервісів (правильний порядок)
    Write-Log "Stopping services for update..."
    
    $stopOrder = @("telegraf", "grafana", "pgadmin", "redis", "timescaledb")
    
    foreach ($service in $stopOrder) {
        if ($Component -eq "all" -or $Component -eq $service) {
            Write-Log "Stopping $service..."
            docker compose -f docker-compose.local.yml stop $service
            Start-Sleep -Seconds 5
        }
    }
    
    # 4. Оновлення сервісів
    Write-Log "Updating services..."
    
    if ($Component -eq "all") {
        # Оновлення всіх сервісів
        docker compose -f docker-compose.local.yml up -d
    } else {
        # Оновлення конкретного сервісу
        docker compose -f docker-compose.local.yml up -d $Component
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start services after update"
    }
    
    Write-Log "✅ Services started"
    
    # 5. Очікування запуску
    Write-Log "Waiting for services to start..."
    Start-Sleep -Seconds 30
    
    # 6. Перевірка здоров'я сервісів
    Write-Log "Checking service health..."
    
    $services = @("timescaledb", "grafana", "telegraf", "pgadmin", "redis")
    $healthyServices = 0
    $totalServices = $services.Count
    
    foreach ($service in $services) {
        if ($Component -eq "all" -or $Component -eq $service) {
            $maxRetries = 10
            $retryCount = 0
            $isHealthy = $false
            
            while ($retryCount -lt $maxRetries -and -not $isHealthy) {
                $isHealthy = Test-ServiceHealthy $service
                if (-not $isHealthy) {
                    Write-Log "Waiting for $service to become healthy... (attempt $($retryCount + 1)/$maxRetries)"
                    Start-Sleep -Seconds 10
                    $retryCount++
                }
            }
            
            if ($isHealthy) {
                Write-Log "✅ $service is healthy"
                $healthyServices++
            } else {
                Write-Log "❌ $service failed to become healthy"
            }
        } else {
            # Сервіс не оновлювався, перевіряємо поточний стан
            if (Test-ServiceHealthy $service) {
                Write-Log "✅ $service is healthy (not updated)"
                $healthyServices++
            } else {
                Write-Log "⚠️  $service is not healthy (not updated)"
            }
        }
    }
    
    # 7. Очищення старих образів
    if ($Force) {
        Write-Log "Cleaning up old Docker images..."
        docker image prune -f
        Write-Log "✅ Old images cleaned up"
    }
    
    # 8. Перевірка доступності сервісів
    Write-Log "Testing service accessibility..."
    
    # Grafana
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Log "✅ Grafana is accessible"
        }
    } catch {
        Write-Log "❌ Grafana is not accessible"
    }
    
    # TimescaleDB
    try {
        $result = docker exec timescaledb pg_isready -U postgres -d telemetry 2>$null
        if ($result -match "accepting connections") {
            Write-Log "✅ TimescaleDB is accessible"
        }
    } catch {
        Write-Log "❌ TimescaleDB is not accessible"
    }
    
    # 9. Підсумок
    Write-Log "Update process completed"
    Write-Log "Healthy services: $healthyServices/$totalServices"
    
    if ($healthyServices -eq $totalServices) {
        Write-Log "🎉 All services are healthy after update!"
        Write-Host "✅ Update completed successfully!" -ForegroundColor Green
        Write-Host "All services are running and healthy" -ForegroundColor Green
    } else {
        Write-Log "⚠️  Some services may need attention"
        Write-Host "⚠️  Update completed with warnings" -ForegroundColor Yellow
        Write-Host "Check logs: docker compose -f docker-compose.local.yml logs" -ForegroundColor Yellow
    }
    
    # 10. Рекомендації
    Write-Log "Post-update recommendations:"
    Write-Log "1. Run diagnostic script: .\scripts\diagnostic.ps1"
    Write-Log "2. Check service logs for any issues"
    Write-Log "3. Test all functionality"
    Write-Log "4. Update documentation if needed"
    
} catch {
    Write-Log "❌ Update failed: $($_.Exception.Message)"
    Write-Log "Stack trace: $($_.ScriptStackTrace)"
    Write-Host "❌ Update failed: $($_.Exception.Message)" -ForegroundColor Red
    
    # Спроба відновлення
    Write-Log "Attempting to restore services..."
    docker compose -f docker-compose.local.yml up -d
    
    Write-Host "Attempting to restore services..." -ForegroundColor Yellow
    Write-Host "Check logs for details: $LogFile" -ForegroundColor Yellow
    
    exit 1
}

Write-Log "Update script completed"
