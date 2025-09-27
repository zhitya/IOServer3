# 🚀 Швидкий старт - Телеметрійний стек

**Для адміністраторів, які хочуть швидко розгорнути систему**

---

## ⚡ Швидке розгортання (5 хвилин)

### **1. Підготовка (1 хвилина)**
```powershell
# Встановіть Docker Desktop з https://www.docker.com/products/docker-desktop/
# Перезапустіть комп'ютер після встановлення

# Перевірка встановлення
docker --version
docker compose version
```

### **2. Завантаження проєкту (1 хвилина)**
```powershell
# Створіть папку (БЕЗ ПРОБІЛІВ у шляху!)
mkdir C:\TelemetryStack
cd C:\TelemetryStack

# Скопіюйте всі файли проєкту в цю папку
# Створіть .env файл
Copy-Item env.local.example .env
```

### **3. Налаштування паролів (1 хвилина)**
```powershell
# Відкрийте .env файл та змініть паролі
notepad .env

# Обов'язково змініть:
# POSTGRES_PASSWORD=YourSecurePassword123!
# GF_SECURITY_ADMIN_PASSWORD=YourGrafanaPassword123!
# PGADMIN_DEFAULT_PASSWORD=YourPgAdminPassword123!
```

### **4. Запуск системи (2 хвилини)**
```powershell
# Завантаження образів
docker compose -f docker-compose.local.yml pull

# Запуск сервісів
docker compose -f docker-compose.local.yml up -d

# Очікування запуску (30 секунд)
Start-Sleep -Seconds 30

# Перевірка статусу
docker compose -f docker-compose.local.yml ps
```

### **5. Перевірка роботи**
```powershell
# Запуск діагностики
.\scripts\diagnostic.ps1

# Перевірка доступності
# Grafana: http://localhost:3000
# pgAdmin: http://localhost:5050
```

---

## 🔧 Швидкі команди

### **Щоденні операції**
```powershell
# Перевірка статусу
docker compose -f docker-compose.local.yml ps

# Перегляд логів
docker compose -f docker-compose.local.yml logs

# Перезапуск всіх сервісів
docker compose -f docker-compose.local.yml restart

# Зупинка системи
docker compose -f docker-compose.local.yml stop
```

### **Діагностика**
```powershell
# Повна діагностика
.\scripts\diagnostic.ps1

# Перевірка здоров'я
docker compose -f docker-compose.local.yml ps --format "table {{.Name}}\t{{.Status}}"

# Перевірка ресурсів
docker stats --no-stream
```

### **Бекапи**
```powershell
# Швидкий бекап
.\scripts\backup.ps1

# Бекап тільки БД
.\scripts\backup.ps1 -DatabaseOnly

# Бекап з архівуванням
.\scripts\backup.ps1 -Compress
```

---

## ⚙️ Налаштування Telegraf

### **Додавання Modbus пристрою**
```powershell
# Додати Modbus TCP пристрій
.\scripts\telegraf-config-helper.ps1 -Action add-modbus -DeviceIP 192.168.1.100 -DeviceName compressor1

# Тестування конфігурації
.\scripts\telegraf-config-helper.ps1 -Action test-config

# Перезапуск Telegraf
docker compose -f docker-compose.local.yml restart telegraf
```

### **Додавання моніторингу мережі**
```powershell
# Моніторинг мережі
.\scripts\telegraf-config-helper.ps1 -Action add-network

# Системний моніторинг
.\scripts\telegraf-config-helper.ps1 -Action add-system
```

---

## 🌐 Веб доступ

### **Локальний доступ**
- **Grafana:** http://localhost:3000
- **pgAdmin:** http://localhost:5050
- **TimescaleDB:** localhost:5432

### **Доступ з мережі**
```powershell
# Дозвіл доступу через фаєрвол
netsh advfirewall firewall add rule name="Grafana HTTP" dir=in action=allow protocol=TCP localport=3000
netsh advfirewall firewall add rule name="pgAdmin HTTP" dir=in action=allow protocol=TCP localport=5050

# Доступ з інших комп'ютерів:
# http://YOUR_SERVER_IP:3000
# http://YOUR_SERVER_IP:5050
```

---

## 🔄 Автозапуск

### **Метод 1: Task Scheduler (рекомендований)**
```powershell
# Створіть завдання в Task Scheduler:
# - Trigger: At startup
# - Action: Start a program
# - Program: powershell.exe
# - Arguments: -ExecutionPolicy Bypass -File "C:\TelemetryStack\scripts\auto-start.ps1"
```

### **Метод 2: Docker Desktop автозапуск**
```powershell
# В Docker Desktop → Settings → General
# Увімкніть "Start Docker Desktop when you log in"
```

---

## 🆘 Швидке вирішення проблем

### **Сервіси не запускаються**
```powershell
# Повний перезапуск
docker compose -f docker-compose.local.yml down
docker compose -f docker-compose.local.yml up -d
```

### **Grafana не відкривається**
```powershell
# Перевірка логів
docker compose -f docker-compose.local.yml logs grafana

# Перезапуск Grafana
docker compose -f docker-compose.local.yml restart grafana
```

### **Telegraf не збирає дані**
```powershell
# Тестування конфігурації
.\scripts\telegraf-config-helper.ps1 -Action test-config

# Перевірка логів
docker compose -f docker-compose.local.yml logs telegraf
```

### **Високе використання ресурсів**
```powershell
# Перевірка ресурсів
docker stats

# Очищення системи
docker system prune -f
```

---

## 📊 Моніторинг

### **Перевірка даних в БД**
```sql
-- Підключення до TimescaleDB через pgAdmin
-- Або через командний рядок:
docker exec -it timescaledb psql -U postgres -d telemetry

-- Перевірка даних
SELECT * FROM telemetry ORDER BY ts DESC LIMIT 10;
SELECT COUNT(*) FROM metrics;
```

### **Grafana дашборди**
1. Відкрийте http://localhost:3000
2. Логін: admin / (пароль з .env)
3. Створіть новий дашборд
4. Додайте панель з запитом:
```sql
SELECT ts AS "time", value
FROM telemetry
WHERE device_id = 'device1'
  AND point = 'Voltage_L1'
  AND $__timeFilter(ts)
ORDER BY ts;
```

---

## 📞 Підтримка

**Швидкі команди для діагностики:**
```powershell
# Повна діагностика
.\scripts\diagnostic.ps1 -Export

# Бекап перед змінами
.\scripts\backup.ps1

# Оновлення системи
.\scripts\update-stack.ps1
```

**Корисні файли:**
- `ADMIN_GUIDE.md` - Повна інструкція адміністратора
- `scripts/` - Скрипти автоматизації
- `logs/` - Логи системи

---

**⚠️ Важливо:** Завжди створюйте бекап перед внесенням змін!

**🎯 Мета:** Швидко розгорнути та налаштувати телеметрійний стек для промислового середовища.
