# 📋 Інструкція адміністратора - Телеметрійний стек

**Версія:** 1.0  
**Дата:** 2025-01-25  
**Проєкт:** Modbus → TimescaleDB → Grafana Stack

---

## 📑 Зміст

1. [Системні вимоги](#1-системні-вимоги)
2. [Розгортання з нуля](#2-розгортання-з-нуля)
3. [Автозапуск з ОС](#3-автозапуск-з-ос)
4. [Діагностика компонентів](#4-діагностика-компонентів)
5. [Бекапи проєкту](#5-бекапи-проєкту)
6. [Оновлення проєкту](#6-оновлення-проєкту)
7. [Веб доступ до Grafana](#7-веб-доступ-до-grafana)
8. [Обслуговування](#8-обслуговування)
9. [Налаштування Telegraf](#9-налаштування-telegraf)
10. [Типові проблеми](#10-типові-проблеми)

---

## 1. Системні вимоги

### **Мінімальні вимоги:**
- **ОС:** Windows 10/11 Pro/Enterprise
- **RAM:** 8 GB (рекомендовано 16 GB)
- **Диск:** 50 GB вільного місця
- **CPU:** 4 ядра (рекомендовано 8 ядер)
- **Мережа:** Ethernet зі статичним IP

### **Програмне забезпечення:**
- **Docker Desktop** 4.20+ з WSL2
- **PowerShell** 7.0+
- **Git** (опціонально)

---

## 2. Розгортання з нуля

### **Крок 1: Підготовка системи**

```powershell
# 1. Встановлення Docker Desktop
# Завантажте з https://www.docker.com/products/docker-desktop/
# Встановіть з опцією "Use WSL 2 based engine"

# 2. Перевірка встановлення
docker --version
docker compose version

# 3. Включення WSL2
wsl --install
wsl --set-default-version 2
```

### **Крок 2: Створення структури проєкту**

```powershell
# Створення робочої папки (без пробілів у шляху!)
mkdir C:\TelemetryStack
cd C:\TelemetryStack

# Створення структури папок
mkdir timescaledb\data, timescaledb\init
mkdir grafana\data, grafana\provisioning\datasources
mkdir telegraf, pgadmin, redis\data, nginx\ssl
mkdir scripts, backups, logs
```

### **Крок 3: Копіювання файлів проєкту**

```powershell
# Скопіюйте всі файли з поточного проєкту:
# - docker-compose.local.yml
# - env.local.example
# - timescaledb\init\01-init.sql
# - grafana\provisioning\datasources\datasource.yml
# - telegraf\telegraf.conf
# - nginx\nginx.conf
```

### **Крок 4: Налаштування змінних середовища**

```powershell
# Створення .env файлу
Copy-Item env.local.example .env

# Редагування .env файлу (ОБОВ'ЯЗКОВО змініть паролі!)
notepad .env
```

**Приклад .env файлу:**
```env
# Database Configuration
POSTGRES_USER=postgres
POSTGRES_PASSWORD=YourSecurePassword123!
POSTGRES_DB=telemetry

# Grafana Configuration
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=YourGrafanaPassword123!

# pgAdmin Configuration
PGADMIN_DEFAULT_EMAIL=admin@yourcompany.com
PGADMIN_DEFAULT_PASSWORD=YourPgAdminPassword123!

# Service Passwords
TELEGRAF_DB_PASSWORD=YourTelegrafPassword123!
GRAFANA_DB_PASSWORD=YourGrafanaDbPassword123!

# Security Keys
GRAFANA_SECRET_KEY=YourSecretKey12345678901234567890
REDIS_PASSWORD=YourRedisPassword123!

# Network Configuration
NETWORK_MODE=local
```

### **Крок 5: Перший запуск**

```powershell
# Завантаження образів
docker compose -f docker-compose.local.yml pull

# Запуск сервісів
docker compose -f docker-compose.local.yml up -d

# Перевірка статусу
docker compose -f docker-compose.local.yml ps
```

### **Крок 6: Перевірка роботи**

```powershell
# Перевірка логів
docker compose -f docker-compose.local.yml logs

# Перевірка доступності сервісів
# Grafana: http://localhost:3000
# pgAdmin: http://localhost:5050
# TimescaleDB: localhost:5432
```

---

## 3. Автозапуск з ОС

### **Метод 1: Docker Desktop автозапуск (рекомендований)**

```powershell
# 1. Відкрийте Docker Desktop
# 2. Перейдіть в Settings → General
# 3. Увімкніть "Start Docker Desktop when you log in"

# 4. Створіть скрипт автозапуску
@"
# Auto-start script for Telemetry Stack
cd C:\TelemetryStack
docker compose -f docker-compose.local.yml up -d
"@ | Out-File -FilePath "C:\TelemetryStack\scripts\auto-start.ps1" -Encoding UTF8

# 5. Створіть завдання в Task Scheduler
# - Trigger: At startup
# - Action: Start a program
# - Program: powershell.exe
# - Arguments: -ExecutionPolicy Bypass -File "C:\TelemetryStack\scripts\auto-start.ps1"
```

### **Метод 2: Windows Service (для серверів)**

```powershell
# Встановлення NSSM (Non-Sucking Service Manager)
# Завантажте з https://nssm.cc/download

# Створення сервісу
nssm install TelemetryStack "C:\TelemetryStack\scripts\auto-start.ps1"
nssm set TelemetryStack Start SERVICE_AUTO_START
nssm start TelemetryStack
```

### **Метод 3: Batch файл в автозавантаженні**

```powershell
# Створення batch файлу
@"
@echo off
cd /d C:\TelemetryStack
docker compose -f docker-compose.local.yml up -d
"@ | Out-File -FilePath "C:\TelemetryStack\scripts\start-stack.bat" -Encoding ASCII

# Копіювання в автозавантаження
Copy-Item "C:\TelemetryStack\scripts\start-stack.bat" "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\"
```

---

## 4. Діагностика компонентів

### **Скрипт автоматичної діагностики**

```powershell
# Створення скрипту діагностики
@"
# Telemetry Stack Diagnostic Script
Write-Host "=== Telemetry Stack Diagnostic ===" -ForegroundColor Green

# 1. Перевірка Docker
Write-Host "`n1. Docker Status:" -ForegroundColor Yellow
docker --version
docker compose version

# 2. Перевірка контейнерів
Write-Host "`n2. Container Status:" -ForegroundColor Yellow
docker compose -f docker-compose.local.yml ps

# 3. Перевірка здоров'я сервісів
Write-Host "`n3. Health Checks:" -ForegroundColor Yellow
$services = @("timescaledb", "grafana", "telegraf", "pgadmin", "redis")

foreach ($service in $services) {
    $status = docker inspect ${service}_1 --format "{{.State.Health.Status}}" 2>$null
    if ($status -eq "healthy") {
        Write-Host "✅ $service: $status" -ForegroundColor Green
    } elseif ($status -eq "unhealthy") {
        Write-Host "❌ $service: $status" -ForegroundColor Red
    } else {
        Write-Host "⚠️  $service: $status" -ForegroundColor Yellow
    }
}

# 4. Перевірка ресурсів
Write-Host "`n4. Resource Usage:" -ForegroundColor Yellow
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# 5. Перевірка логів на помилки
Write-Host "`n5. Recent Errors:" -ForegroundColor Yellow
docker compose -f docker-compose.local.yml logs --tail=10 | Select-String -Pattern "error|Error|ERROR|fatal|Fatal|FATAL"

# 6. Перевірка доступності сервісів
Write-Host "`n6. Service Accessibility:" -ForegroundColor Yellow

# Grafana
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Grafana: Accessible" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Grafana: Not accessible" -ForegroundColor Red
}

# TimescaleDB
try {
    $result = docker exec timescaledb pg_isready -U postgres -d telemetry 2>$null
    if ($result -match "accepting connections") {
        Write-Host "✅ TimescaleDB: Accepting connections" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ TimescaleDB: Not accessible" -ForegroundColor Red
}

# 7. Перевірка розміру даних
Write-Host "`n7. Data Size:" -ForegroundColor Yellow
$timescaleSize = (Get-ChildItem ".\timescaledb\data" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
$grafanaSize = (Get-ChildItem ".\grafana\data" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum

Write-Host "TimescaleDB: $([math]::Round($timescaleSize/1GB,2)) GB" -ForegroundColor Blue
Write-Host "Grafana: $([math]::Round($grafanaSize/1GB,2)) GB" -ForegroundColor Blue

Write-Host "`n=== Diagnostic Complete ===" -ForegroundColor Green
"@ | Out-File -FilePath "C:\TelemetryStack\scripts\diagnostic.ps1" -Encoding UTF8
```

### **Ручна діагностика**

```powershell
# Перевірка статусу всіх сервісів
docker compose -f docker-compose.local.yml ps

# Перевірка логів конкретного сервісу
docker compose -f docker-compose.local.yml logs timescaledb
docker compose -f docker-compose.local.yml logs grafana
docker compose -f docker-compose.local.yml logs telegraf

# Перевірка ресурсів
docker stats

# Перевірка мережі
docker network ls
docker network inspect telemetrystack_default

# Перевірка volumes
docker volume ls
```

---

## 5. Бекапи проєкту

### **Автоматичні бекапи**

```powershell
# Створення скрипту бекапу
@"
# Backup Script for Telemetry Stack
$backupDir = "C:\TelemetryStack\backups"
$date = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = "$backupDir\backup_$date"

Write-Host "Starting backup at $date" -ForegroundColor Green

# 1. Створення папки бекапу
New-Item -ItemType Directory -Path $backupPath -Force

# 2. Бекап бази даних
Write-Host "Backing up TimescaleDB..." -ForegroundColor Yellow
docker exec timescaledb pg_dump -U postgres -d telemetry > "$backupPath\telemetry_dump.sql"

# 3. Бекап конфігурацій
Write-Host "Backing up configurations..." -ForegroundColor Yellow
Copy-Item ".\docker-compose.local.yml" "$backupPath\"
Copy-Item "\.env" "$backupPath\"
Copy-Item ".\grafana\provisioning" "$backupPath\grafana_provisioning" -Recurse
Copy-Item ".\telegraf\telegraf.conf" "$backupPath\"

# 4. Бекап даних Grafana
Write-Host "Backing up Grafana data..." -ForegroundColor Yellow
Copy-Item ".\grafana\data" "$backupPath\grafana_data" -Recurse

# 5. Створення архіву
Write-Host "Creating archive..." -ForegroundColor Yellow
Compress-Archive -Path "$backupPath\*" -DestinationPath "$backupDir\telemetry_backup_$date.zip"

# 6. Очищення тимчасової папки
Remove-Item $backupPath -Recurse -Force

# 7. Видалення старих бекапів (старше 30 днів)
Get-ChildItem $backupDir -Filter "*.zip" | Where-Object {$_.CreationTime -lt (Get-Date).AddDays(-30)} | Remove-Item

Write-Host "Backup completed: $backupDir\telemetry_backup_$date.zip" -ForegroundColor Green
"@ | Out-File -FilePath "C:\TelemetryStack\scripts\backup.ps1" -Encoding UTF8
```

### **Ручні бекапи**

```powershell
# Бекап бази даних
docker exec timescaledb pg_dump -U postgres -d telemetry > backup_$(Get-Date -Format "yyyyMMdd_HHmmss").sql

# Бекап всього проєкту
Compress-Archive -Path ".\*" -DestinationPath "telemetry_stack_backup_$(Get-Date -Format "yyyyMMdd_HHmmss").zip"

# Бекап тільки конфігурацій
Copy-Item ".\docker-compose.local.yml" ".\backups\"
Copy-Item "\.env" ".\backups\"
Copy-Item ".\grafana\provisioning" ".\backups\grafana_provisioning" -Recurse
```

### **Відновлення з бекапу**

```powershell
# Відновлення бази даних
docker exec -i timescaledb psql -U postgres -d telemetry < backup_file.sql

# Відновлення всього проєкту
Expand-Archive -Path "telemetry_stack_backup.zip" -DestinationPath "C:\TelemetryStack\restored"
```

---

## 6. Оновлення проєкту

### **Оновлення окремих компонентів**

```powershell
# Оновлення конкретного сервісу
docker compose -f docker-compose.local.yml pull grafana
docker compose -f docker-compose.local.yml up -d grafana

# Оновлення всіх сервісів
docker compose -f docker-compose.local.yml pull
docker compose -f docker-compose.local.yml up -d
```

### **Оновлення конфігурацій**

```powershell
# 1. Створіть бекап перед змінами
.\scripts\backup.ps1

# 2. Зупиніть сервіси
docker compose -f docker-compose.local.yml stop

# 3. Внесіть зміни в конфігурації
# - telegraf.conf
# - datasource.yml
# - docker-compose.local.yml

# 4. Запустіть сервіси
docker compose -f docker-compose.local.yml up -d

# 5. Перевірте роботу
.\scripts\diagnostic.ps1
```

### **Оновлення всього проєкту**

```powershell
# 1. Повний бекап
.\scripts\backup.ps1

# 2. Зупинка всіх сервісів
docker compose -f docker-compose.local.yml down

# 3. Оновлення образів
docker compose -f docker-compose.local.yml pull

# 4. Очищення старих образів
docker image prune -f

# 5. Запуск з новими образами
docker compose -f docker-compose.local.yml up -d

# 6. Перевірка
.\scripts\diagnostic.ps1
```

---

## 7. Веб доступ до Grafana

### **Налаштування доступу з мережі**

```powershell
# 1. Перевірка IP адреси
ipconfig

# 2. Налаштування Windows Firewall
netsh advfirewall firewall add rule name="Grafana HTTP" dir=in action=allow protocol=TCP localport=3000
netsh advfirewall firewall add rule name="pgAdmin HTTP" dir=in action=allow protocol=TCP localport=5050

# 3. Налаштування Grafana для мережі
# Додайте в .env файл:
# GF_SERVER_ROOT_URL=http://YOUR_IP:3000
# GF_SERVER_DOMAIN=YOUR_IP
```

### **Налаштування Nginx як проксі (опціонально)**

```yaml
# Додайте в docker-compose.local.yml
nginx:
  image: nginx:alpine
  container_name: nginx
  ports:
    - "80:80"
    - "443:443"
  volumes:
    - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
  depends_on:
    - grafana
    - pgadmin
```

### **Доступ з віддалених комп'ютерів**

```powershell
# URL для доступу:
# Grafana: http://YOUR_SERVER_IP:3000
# pgAdmin: http://YOUR_SERVER_IP:5050

# Перевірка доступності
Test-NetConnection -ComputerName YOUR_SERVER_IP -Port 3000
Test-NetConnection -ComputerName YOUR_SERVER_IP -Port 5050
```

---

## 8. Обслуговування

### **Правильне зупинення для обслуговування**

```powershell
# 1. Створення бекапу
.\scripts\backup.ps1

# 2. Зупинка сервісів (правильний порядок)
docker compose -f docker-compose.local.yml stop telegraf
docker compose -f docker-compose.local.yml stop grafana
docker compose -f docker-compose.local.yml stop pgadmin
docker compose -f docker-compose.local.yml stop timescaledb

# 3. Перевірка зупинки
docker compose -f docker-compose.local.yml ps
```

### **Планове обслуговування**

```powershell
# Щомісячне обслуговування
# 1. Очищення логів
docker system prune -f

# 2. Оновлення образів
docker compose -f docker-compose.local.yml pull

# 3. Перевірка здоров'я
.\scripts\diagnostic.ps1

# 4. Очищення старих бекапів
Get-ChildItem ".\backups" -Filter "*.zip" | Where-Object {$_.CreationTime -lt (Get-Date).AddDays(-90)} | Remove-Item
```

### **Екстрене відновлення**

```powershell
# Якщо сервіси не запускаються
docker compose -f docker-compose.local.yml down
docker system prune -f
docker compose -f docker-compose.local.yml up -d

# Якщо база даних пошкоджена
docker exec timescaledb pg_resetwal /var/lib/postgresql/data
docker compose -f docker-compose.local.yml restart timescaledb
```

---

## 9. Налаштування Telegraf

### **Зміна налаштувань Modbus TCP**

```toml
# Файл: telegraf/telegraf.conf
[[inputs.modbus]]
  name = "modbus"
  controller = "tcp://192.168.1.100:502"  # IP вашого Modbus пристрою
  slave_id = 1
  timeout = "2s"
  retries = 3
  
  [inputs.modbus.tags]
    device_id = "compressor_1"
    location = "plant_floor"
    protocol = "modbus_tcp"

  # Напруга
  [[inputs.modbus.holding_registers]]
    name = "Voltage_L1"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.1
    address = [0]

  # Струм
  [[inputs.modbus.holding_registers]]
    name = "Current_L1"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.01
    address = [1]

  # Потужність (32-біт)
  [[inputs.modbus.holding_registers]]
    name = "Power_Total"
    data_type = "FLOAT32-IEEE"
    byte_order = "ABCD"
    scale = 1.0
    address = [50, 51]
```

### **Додавання моніторингу комп'ютерів мережі**

```toml
# Додайте в telegraf.conf для моніторингу мережі
[[inputs.ping]]
  urls = ["192.168.1.10", "192.168.1.20", "192.168.1.30"]
  count = 3
  ping_interval = 1.0
  timeout = 3.0

[[inputs.snmp]]
  agents = ["192.168.1.10:161", "192.168.1.20:161"]
  community = "public"
  version = 2
  
  [[inputs.snmp.field]]
    name = "hostname"
    oid = "1.3.6.1.2.1.1.5.0"
```

### **Застосування змін**

```powershell
# 1. Зупинка Telegraf
docker compose -f docker-compose.local.yml stop telegraf

# 2. Редагування конфігурації
notepad .\telegraf\telegraf.conf

# 3. Тестування конфігурації
docker exec telegraf telegraf --config /etc/telegraf/telegraf.conf --test

# 4. Запуск Telegraf
docker compose -f docker-compose.local.yml up -d telegraf

# 5. Перевірка логів
docker compose -f docker-compose.local.yml logs telegraf
```

---

## 10. Типові проблеми

### **Проблема: Контейнери не запускаються**

```powershell
# Рішення:
docker compose -f docker-compose.local.yml down
docker system prune -f
docker compose -f docker-compose.local.yml up -d
```

### **Проблема: Grafana не підключається до БД**

```powershell
# Перевірка з'єднання
docker exec timescaledb psql -U postgres -d telemetry -c "SELECT 1;"

# Перевірка паролів в .env
# Перевірка datasource.yml
```

### **Проблема: Telegraf не збирає дані**

```powershell
# Перевірка конфігурації
docker exec telegraf telegraf --config /etc/telegraf/telegraf.conf --test

# Перевірка з'єднання з Modbus
telnet 192.168.1.100 502

# Перевірка логів
docker logs telegraf
```

### **Проблема: Високе використання ресурсів**

```powershell
# Перевірка ресурсів
docker stats

# Обмеження ресурсів в docker-compose.local.yml
deploy:
  resources:
    limits:
      memory: 1G
      cpus: '0.5'
```

---

## 📞 Підтримка

**Контакти:**
- **Email:** info@askue.net
- **Телефон:** +380-50-228-228-0
- **Документація:** [Внутрішня база знань]

**Корисні команди:**
```powershell
# Швидка діагностика
.\scripts\diagnostic.ps1

# Швидкий бекап
.\scripts\backup.ps1

# Перезапуск всіх сервісів
docker compose -f docker-compose.local.yml restart

# Перегляд логів
docker compose -f docker-compose.local.yml logs -f
```

---

**⚠️ Важливо:** Завжди створюйте бекап перед внесенням змін!

**📅 Останнє оновлення:** 2025-01-25  
**👤 Автор:** Системний адміністратор
