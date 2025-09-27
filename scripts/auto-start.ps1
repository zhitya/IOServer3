# Auto-start script for Telemetry Stack
# Запускає всі сервіси при старті системи

param(
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Логування
$LogFile = "C:\TelemetryStack\logs\auto-start.log"
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

try {
    Write-Log "Starting Telemetry Stack auto-start script"
    
    # Перехід в робочу папку
    Set-Location "C:\TelemetryStack"
    
    # Перевірка наявності Docker
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker not found. Please install Docker Desktop."
    }
    
    # Перевірка наявності docker-compose файлу
    if (-not (Test-Path "docker-compose.local.yml")) {
        throw "docker-compose.local.yml not found in C:\TelemetryStack"
    }
    
    # Перевірка наявності .env файлу
    if (-not (Test-Path ".env")) {
        throw ".env file not found. Please create it from env.local.example"
    }
    
    # Запуск сервісів
    Write-Log "Starting Docker Compose services..."
    docker compose -f docker-compose.local.yml up -d
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start Docker Compose services"
    }
    
    # Очікування запуску сервісів
    Write-Log "Waiting for services to start..."
    Start-Sleep -Seconds 30
    
    # Перевірка статусу сервісів
    Write-Log "Checking service status..."
    $services = docker compose -f docker-compose.local.yml ps --format "table {{.Name}}\t{{.Status}}"
    Write-Log "Service status:`n$services"
    
    # Перевірка здоров'я ключових сервісів
    $healthyServices = 0
    $totalServices = 5
    
    $services = @("timescaledb", "grafana", "telegraf", "pgadmin", "redis")
    foreach ($service in $services) {
        try {
            $health = docker inspect "${service}_1" --format "{{.State.Health.Status}}" 2>$null
            if ($health -eq "healthy") {
                Write-Log "✅ $service is healthy"
                $healthyServices++
            } else {
                Write-Log "⚠️  $service status: $health"
            }
        } catch {
            Write-Log "❌ Failed to check $service health"
        }
    }
    
    if ($healthyServices -eq $totalServices) {
        Write-Log "🎉 All services started successfully!"
        Write-Log "Grafana: http://localhost:3000"
        Write-Log "pgAdmin: http://localhost:5050"
    } else {
        Write-Log "⚠️  Some services may not be fully ready. Check logs:"
        Write-Log "docker compose -f docker-compose.local.yml logs"
    }
    
} catch {
    Write-Log "❌ Error: $($_.Exception.Message)"
    Write-Log "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}

Write-Log "Auto-start script completed"
