# Comprehensive Backup Script for Telemetry Stack
# Створює повний бекап системи з архівуванням

param(
    [string]$BackupPath = "C:\TelemetryStack\backups",
    [int]$RetentionDays = 30,
    [switch]$Compress,
    [switch]$DatabaseOnly,
    [switch]$ConfigOnly
)

$ErrorActionPreference = "Stop"

# Логування
$LogFile = "C:\TelemetryStack\logs\backup.log"
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

function Test-ServiceRunning {
    param($ServiceName)
    try {
        $status = docker inspect "${ServiceName}_1" --format "{{.State.Status}}" 2>$null
        return $status -eq "running"
    } catch {
        return $false
    }
}

try {
    Write-Log "Starting Telemetry Stack backup process"
    
    # Створення папки бекапу
    $date = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = "$BackupPath\backup_$date"
    
    if (-not (Test-Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force
        Write-Log "Created backup directory: $BackupPath"
    }
    
    New-Item -ItemType Directory -Path $backupDir -Force
    Write-Log "Created backup directory: $backupDir"
    
    # 1. Бекап бази даних
    if (-not $ConfigOnly) {
        Write-Log "Starting database backup..."
        
        if (Test-ServiceRunning "timescaledb") {
            # Повний бекап бази даних
            $dbBackupFile = "$backupDir\telemetry_full_backup.sql"
            Write-Log "Creating full database backup..."
            
            docker exec timescaledb pg_dump -U postgres -d telemetry --verbose --no-password > $dbBackupFile
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "✅ Database backup completed: $dbBackupFile"
                
                # Перевірка розміру бекапу
                $backupSize = (Get-Item $dbBackupFile).Length
                $backupSizeMB = [math]::Round($backupSize / 1MB, 2)
                Write-Log "Database backup size: $backupSizeMB MB"
            } else {
                throw "Database backup failed with exit code $LASTEXITCODE"
            }
            
            # Додатковий бекап тільки структури
            $schemaBackupFile = "$backupDir\telemetry_schema_only.sql"
            Write-Log "Creating schema-only backup..."
            
            docker exec timescaledb pg_dump -U postgres -d telemetry --schema-only --no-password > $schemaBackupFile
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "✅ Schema backup completed: $schemaBackupFile"
            }
            
        } else {
            Write-Log "⚠️  TimescaleDB not running, skipping database backup"
        }
    }
    
    # 2. Бекап конфігурацій
    if (-not $DatabaseOnly) {
        Write-Log "Starting configuration backup..."
        
        # Docker Compose файли
        if (Test-Path "docker-compose.local.yml") {
            Copy-Item "docker-compose.local.yml" "$backupDir\"
            Write-Log "✅ docker-compose.local.yml backed up"
        }
        
        if (Test-Path "docker-compose.yml") {
            Copy-Item "docker-compose.yml" "$backupDir\"
            Write-Log "✅ docker-compose.yml backed up"
        }
        
        # .env файл (без паролів для безпеки)
        if (Test-Path ".env") {
            $envBackup = "$backupDir\.env.backup"
            Copy-Item ".env" $envBackup
            Write-Log "✅ .env file backed up"
        }
        
        # Grafana конфігурації
        if (Test-Path "grafana\provisioning") {
            Copy-Item "grafana\provisioning" "$backupDir\grafana_provisioning" -Recurse
            Write-Log "✅ Grafana provisioning backed up"
        }
        
        # Telegraf конфігурація
        if (Test-Path "telegraf\telegraf.conf") {
            Copy-Item "telegraf\telegraf.conf" "$backupDir\"
            Write-Log "✅ Telegraf configuration backed up"
        }
        
        # Nginx конфігурація
        if (Test-Path "nginx\nginx.conf") {
            Copy-Item "nginx\nginx.conf" "$backupDir\"
            Write-Log "✅ Nginx configuration backed up"
        }
        
        # Скрипти
        if (Test-Path "scripts") {
            Copy-Item "scripts" "$backupDir\scripts" -Recurse
            Write-Log "✅ Scripts backed up"
        }
    }
    
    # 3. Бекап даних Grafana (якщо не тільки БД)
    if (-not $DatabaseOnly -and -not $ConfigOnly) {
        Write-Log "Starting Grafana data backup..."
        
        if (Test-Path "grafana\data") {
            # Бекап тільки важливих файлів Grafana
            $grafanaDataDir = "$backupDir\grafana_data"
            New-Item -ItemType Directory -Path $grafanaDataDir -Force
            
            # Бекап бази даних Grafana
            if (Test-Path "grafana\data\grafana.db") {
                Copy-Item "grafana\data\grafana.db" "$grafanaDataDir\"
                Write-Log "✅ Grafana database backed up"
            }
            
            # Бекап дашбордів
            if (Test-Path "grafana\data\dashboards") {
                Copy-Item "grafana\data\dashboards" "$grafanaDataDir\dashboards" -Recurse
                Write-Log "✅ Grafana dashboards backed up"
            }
            
            # Бекап користувачів
            if (Test-Path "grafana\data\users") {
                Copy-Item "grafana\data\users" "$grafanaDataDir\users" -Recurse
                Write-Log "✅ Grafana users backed up"
            }
        }
    }
    
    # 4. Бекап pgAdmin даних
    if (-not $DatabaseOnly -and -not $ConfigOnly) {
        Write-Log "Starting pgAdmin data backup..."
        
        if (Test-Path "pgadmin") {
            Copy-Item "pgadmin" "$backupDir\pgadmin_data" -Recurse
            Write-Log "✅ pgAdmin data backed up"
        }
    }
    
    # 5. Створення метаданих бекапу
    Write-Log "Creating backup metadata..."
    
    $metadata = @{
        "backup_date" = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "backup_type" = if ($DatabaseOnly) { "database_only" } elseif ($ConfigOnly) { "config_only" } else { "full" }
        "system_info" = @{
            "os" = (Get-WmiObject -Class Win32_OperatingSystem).Caption
            "docker_version" = (docker --version)
            "compose_version" = (docker compose version)
        }
        "services_status" = @{
            "timescaledb" = Test-ServiceRunning "timescaledb"
            "grafana" = Test-ServiceRunning "grafana"
            "telegraf" = Test-ServiceRunning "telegraf"
            "pgadmin" = Test-ServiceRunning "pgadmin"
            "redis" = Test-ServiceRunning "redis"
        }
        "data_sizes" = @{
            "timescaledb" = if (Test-Path "timescaledb\data") { [math]::Round(((Get-ChildItem "timescaledb\data" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB), 2) } else { 0 }
            "grafana" = if (Test-Path "grafana\data") { [math]::Round(((Get-ChildItem "grafana\data" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB), 2) } else { 0 }
            "pgadmin" = if (Test-Path "pgadmin") { [math]::Round(((Get-ChildItem "pgadmin" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB), 2) } else { 0 }
        }
    }
    
    $metadata | ConvertTo-Json -Depth 3 | Out-File -FilePath "$backupDir\backup_metadata.json" -Encoding UTF8
    Write-Log "✅ Backup metadata created"
    
    # 6. Архівування (якщо вказано)
    if ($Compress) {
        Write-Log "Creating compressed archive..."
        
        $archiveFile = "$BackupPath\telemetry_backup_$date.zip"
        Compress-Archive -Path "$backupDir\*" -DestinationPath $archiveFile -Force
        
        if (Test-Path $archiveFile) {
            $archiveSize = (Get-Item $archiveFile).Length
            $archiveSizeMB = [math]::Round($archiveSize / 1MB, 2)
            Write-Log "✅ Archive created: $archiveFile ($archiveSizeMB MB)"
            
            # Видалення тимчасової папки
            Remove-Item $backupDir -Recurse -Force
            Write-Log "✅ Temporary directory cleaned up"
        } else {
            throw "Failed to create archive"
        }
    }
    
    # 7. Очищення старих бекапів
    Write-Log "Cleaning up old backups..."
    
    $oldBackups = Get-ChildItem $BackupPath -Filter "backup_*" | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays) }
    $oldArchives = Get-ChildItem $BackupPath -Filter "telemetry_backup_*.zip" | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays) }
    
    $totalOldSize = 0
    foreach ($backup in $oldBackups) {
        $totalOldSize += (Get-ChildItem $backup.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Remove-Item $backup.FullName -Recurse -Force
        Write-Log "Deleted old backup: $($backup.Name)"
    }
    
    foreach ($archive in $oldArchives) {
        $totalOldSize += $archive.Length
        Remove-Item $archive.FullName -Force
        Write-Log "Deleted old archive: $($archive.Name)"
    }
    
    if ($totalOldSize -gt 0) {
        $freedSpaceMB = [math]::Round($totalOldSize / 1MB, 2)
        Write-Log "✅ Freed up $freedSpaceMB MB by cleaning old backups"
    }
    
    # 8. Підсумок
    $finalBackupSize = if ($Compress) {
        (Get-Item $archiveFile).Length
    } else {
        (Get-ChildItem $backupDir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    }
    
    $finalSizeMB = [math]::Round($finalBackupSize / 1MB, 2)
    
    Write-Log "🎉 Backup completed successfully!"
    Write-Log "Backup location: $(if ($Compress) { $archiveFile } else { $backupDir })"
    Write-Log "Backup size: $finalSizeMB MB"
    Write-Log "Backup type: $(if ($DatabaseOnly) { 'Database only' } elseif ($ConfigOnly) { 'Configuration only' } else { 'Full backup' })"
    
    Write-Host "✅ Backup completed successfully!" -ForegroundColor Green
    Write-Host "Location: $(if ($Compress) { $archiveFile } else { $backupDir })" -ForegroundColor Blue
    Write-Host "Size: $finalSizeMB MB" -ForegroundColor Blue
    
} catch {
    Write-Log "❌ Backup failed: $($_.Exception.Message)"
    Write-Log "Stack trace: $($_.ScriptStackTrace)"
    Write-Host "❌ Backup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Log "Backup script completed"
