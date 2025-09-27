# Modbus → PostgreSQL/TimescaleDB → Grafana (Windows, Docker) — детальна інструкція

_Оновлено: 2025-09-25_

Цей документ описує **мінімальний, але надійний** стек для збирання телеметрії з **Modbus TCP/RTU**, збереження даних у **TimescaleDB (PostgreSQL)**, побудови **дашбордів у Grafana** та експорту звітів у **CSV** (відкривається у Excel). Усе розгортається на **Windows 10/11** через **Docker Desktop (WSL2)**.

---

## Зміст

- [1. Огляд та цілі](#1-огляд-та-цілі)
- [2. Архітектура](#2-архітектура)
- [3. Вимоги](#3-вимоги)
- [4. Структура проєкту](#4-структура-проєкту)
- [5. Швидкий старт](#5-швидкий-старт)
- [6. Конфігурація компонентів](#6-конфігурація-компонентів)
  - [6.1 TimescaleDB/PostgreSQL](#61-timescaledbpostgresql)
  - [6.2 Telegraf (Modbus → DB)](#62-telegraf-modbus--db)
  - [6.3 Grafana](#63-grafana)
- [7. Симулятор Modbus на Windows (ModRSsim2)](#7-симулятор-modbus-на-windows-modrssim2)
- [8. Типові проблеми та рішення](#8-типові-проблеми-та-рішення)
- [9. Міграція/перенесення на інший хост](#9-міграціявперенесення-на-інший-хост)
- [10. Безпека та прод-хардінг](#10-безпека-та-прод-хардінг)
- [11. Додатки](#11-додатки)
  - [A. Приклади SQL-запитів для Grafana/Excel](#a-приклади-sql-запитів-для-grafanaexcel)
  - [B. Modbus RTU (COM-порт на Windows)](#b-modbus-rtu-com-порт-на-windows)
  - [C. XLSX-звіти (опційно через Metabase)](#c-xlsx-звіти-опційно-через-metabase)

---

## 1. Огляд та цілі

- Збирати телеметрію з **Modbus TCP/RTU** пристроїв.
- Зберігати сирі ряди у **TimescaleDB** з можливістю **агрегації/ретенції/стиску**.
- Візуалізувати у **Grafana**; завантажувати дані у **CSV** для Excel.
- Мінімальний стек, простий у розгортанні та підтримці на Windows.

## 2. Архітектура

```
+------------------+        TCP/RTU        +----------------------------+
|  Modbus пристрій |  <------------------>  |   Telegraf (inputs.modbus) |
+------------------+                        +----------------------------+
                                                  |  outputs.sql (pgx)
                                                  v
                                          +----------------------------+
                                          | TimescaleDB (PostgreSQL)  |
                                          |  - metrics (JSONB)        |
                                          |  - view telemetry         |
                                          |  - telemetry_1h (CA)      |
                                          +----------------------------+
                                                  ^
                                                  |  Postgres datasource
                                                  |
                                          +----------------------------+
                                          |          Grafana           |
                                          |  дашборди + експорт CSV   |
                                          +----------------------------+
```

**Принцип зберігання:** Telegraf пише в універсальну таблицю `metrics(time, measurement, tags jsonb, fields jsonb)`.
Для зручних SQL робимо `VIEW telemetry(ts, device_id, point, value)` і **continuous aggregate** `telemetry_1h`.

## 3. Вимоги

- **Windows 10/11**
- **Docker Desktop** із **WSL2**
- Права адміністратора (відкриття порту 502/TCP для симулятора або реального пристрою)
- Текстовий редактор (VS Code/Notepad++)

## 4. Структура проєкту

```
.  docker-compose.yml
  .env
  grafana    provisioning      datasources        datasource.yml
    data\                (створиться автоматично)
  telegraf    telegraf.conf
  timescaledb    data\                (створиться автоматично)
    init\                (необов’язково для автоскриптів)
```

## 5. Швидкий старт

1. **Склонуйте/скопіюйте** цю структуру на диск без пробілів у шляху (напр., `E:\scada-stack\`).  
2. **Відредагуйте `.env`** (логіни/паролі для локалу):
   ```dotenv
   POSTGRES_USER=postgres
   POSTGRES_PASSWORD=postgres
   POSTGRES_DB=telemetry

   GF_SECURITY_ADMIN_USER=admin
   GF_SECURITY_ADMIN_PASSWORD=admin

   PGADMIN_DEFAULT_EMAIL=admin@example.com
   PGADMIN_DEFAULT_PASSWORD=admin

   TELEGRAF_DB_PASSWORD=telegraf123
   GRAFANA_DB_PASSWORD=grafana123
   ```
3. **Запустіть**:
   ```powershell
   docker compose pull
   docker compose up -d
   ```
4. **Grafana**: http://localhost:3000 (логін/пароль з `.env`).  
5. **pgAdmin** (опційно): http://localhost:5050.  
6. Якщо у БД не створилися об’єкти — виконайте команди з розділу [6.1](#61-timescaledbpostgresql).

## 6. Конфігурація компонентів

### 6.1 TimescaleDB/PostgreSQL

**Docker Compose (фрагмент):**
```yaml
services:
  timescaledb:
    image: timescale/timescaledb:latest-pg16
    container_name: timescaledb
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "5432:5432"
    volumes:
      - ./timescaledb/data:/var/lib/postgresql/data
      - ./timescaledb/init:/docker-entrypoint-initdb.d
```

**Створення об’єктів (якщо init-скрипт не спрацював):**
```powershell
docker exec -it timescaledb psql -U postgres -d telemetry -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"

docker exec -it timescaledb psql -U postgres -d telemetry -c "CREATE TABLE IF NOT EXISTS public.metrics (time timestamptz NOT NULL, measurement text NOT NULL, tags jsonb, fields jsonb);"
docker exec -it timescaledb psql -U postgres -d telemetry -c "SELECT create_hypertable('public.metrics','time', if_not_exists => TRUE);"

# Якщо існує таблиця 'telemetry', яка блокує створення VIEW, перейменуйте її:
docker exec -it timescaledb psql -U postgres -d telemetry -c "ALTER TABLE IF EXISTS public.telemetry RENAME TO telemetry_table_backup;"

docker exec -it timescaledb psql -U postgres -d telemetry -c "CREATE OR REPLACE VIEW public.telemetry AS SELECT time AS ts, COALESCE(tags->>'device_id', tags->>'name','unknown') AS device_id, key AS point, (fields->>key)::double precision AS value FROM public.metrics CROSS JOIN LATERAL jsonb_object_keys(fields) AS key;"

docker exec -it timescaledb psql -U postgres -d telemetry -c "CREATE MATERIALIZED VIEW IF NOT EXISTS public.telemetry_1h WITH (timescaledb.continuous) AS SELECT time_bucket('1 hour', time) AS t, COALESCE(tags->>'device_id', tags->>'name','unknown') AS device_id, key AS point, avg((fields->>key)::double precision) AS avg_v, min((fields->>key)::double precision) AS min_v, max((fields->>key)::double precision) AS max_v FROM public.metrics CROSS JOIN LATERAL jsonb_object_keys(fields) AS key GROUP BY 1,2,3;"

docker exec -it timescaledb psql -U postgres -d telemetry -c "SELECT add_continuous_aggregate_policy('public.telemetry_1h', start_offset => INTERVAL '3 days', end_offset => INTERVAL '1 hour', schedule_interval => INTERVAL '1 hour');"

# Ролі та права (паролі синхронізуйте з Grafana/Telegraf або відкоригуйте):
docker exec -it timescaledb psql -U postgres -d telemetry -c "CREATE ROLE grafana LOGIN PASSWORD 'grafana123';" 2>$null
docker exec -it timescaledb psql -U postgres -d telemetry -c "ALTER  ROLE grafana WITH LOGIN PASSWORD 'grafana123';"

docker exec -it timescaledb psql -U postgres -d telemetry -c "CREATE ROLE telegraf LOGIN PASSWORD 'telegraf123';" 2>$null
docker exec -it timescaledb psql -U postgres -d telemetry -c "ALTER  ROLE telegraf WITH LOGIN PASSWORD 'telegraf123';"

docker exec -it timescaledb psql -U postgres -d telemetry -c "GRANT USAGE ON SCHEMA public TO telegraf, grafana;"
docker exec -it timescaledb psql -U postgres -d telemetry -c "GRANT INSERT, SELECT ON public.metrics TO telegraf;"
docker exec -it timescaledb psql -U postgres -d telemetry -c "GRANT SELECT ON public.metrics, public.telemetry, public.telemetry_1h TO grafana;"
```

> **PowerShell-порада:** для блоків `DO $$ ... $$` використовуйте одинарні лапки навколо всього SQL і подвоєні одинарні всередині, щоб `$` не «з’їдався».

### 6.2 Telegraf (Modbus → DB)

**Docker Compose (фрагмент):**
```yaml
telegraf:
  image: telegraf:1.30
  container_name: telegraf
  restart: unless-stopped
  depends_on:
    - timescaledb
  volumes:
    - ./telegraf/telegraf.conf:/etc/telegraf/telegraf.conf:ro
  environment:
    POSTGRES_HOST: timescaledb
    POSTGRES_DB: ${POSTGRES_DB}
    POSTGRES_USER: telegraf
    POSTGRES_PASSWORD: ${TELEGRAF_DB_PASSWORD}
```

**telegraf.conf (приклад із Modbus TCP на хості Windows):**
```toml
[agent]
  interval = "10s"
  flush_interval = "10s"
  round_interval = true
  omit_hostname = true

[[inputs.modbus]]
  name = "modbus"
  controller = "tcp://host.docker.internal:502"  # доступ до сервісу на хості з контейнера
  slave_id = 1
  timeout = "2s"

  [inputs.modbus.tags]
    device_id = "meter1"

  [[inputs.modbus.holding_registers]]
    name = "Voltage_L1"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.1
    address = [0]   # масив, навіть якщо один регістр

  [[inputs.modbus.holding_registers]]
    name = "Current_L1"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.01
    address = [1]

# 32-біт значення (приклад):
# [[inputs.modbus.holding_registers]]
#   name = "Power_Total"
#   data_type = "FLOAT32-IEEE"
#   byte_order = "ABCD"
#   scale = 1.0
#   address = [52, 53]

[[outputs.sql]]
  driver = "pgx"
  data_source_name = "postgres://telegraf:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/${POSTGRES_DB}?sslmode=disable"
```

**Перевірка:**
```powershell
docker compose restart telegraf
docker logs telegraf --tail=100
docker exec -it telegraf telegraf --config /etc/telegraf/telegraf.conf --test
```

**Очікуваний результат у БД:**
```powershell
docker exec -it timescaledb psql -U postgres -d telemetry -c "SELECT time, measurement, tags, fields FROM metrics ORDER BY time DESC LIMIT 5;"
docker exec -it timescaledb psql -U postgres -d telemetry -c "SELECT ts, device_id, point, value FROM telemetry ORDER BY ts DESC LIMIT 5;"
```

### 6.3 Grafana

**provisioning/datasources/datasource.yml:**
```yaml
apiVersion: 1
datasources:
  - name: TimescaleDB
    type: postgres
    access: proxy
    isDefault: true
    url: timescaledb:5432
    user: grafana
    secureJsonData:
      password: grafana123   # або підстав з env, якщо у вас це працює стабільно
    jsonData:
      database: telemetry
      sslmode: 'disable'
      timescaledb: true
      postgresVersion: 1600
```

**Перевірка підключення в UI:** Data sources → TimescaleDB → **Save & Test**.

**Приклад запиту:**
```sql
SELECT ts AS "time", value
FROM telemetry
WHERE device_id = 'meter1'
  AND point = 'Voltage_L1'
  AND $__timeFilter(ts)
ORDER BY ts;
```

---

## 7. Симулятор Modbus на Windows (ModRSsim2)

- З контейнера використовуйте `host.docker.internal` у `controller`.  
- Відкрийте порт 502/TCP у фаєрволі:
  ```powershell
  netsh advfirewall firewall add rule name="Modbus TCP 502" dir=in action=allow protocol=TCP localport=502
  ```
- Переконайтеся, що сервіс слухає порт:
  ```powershell
  netstat -ano | find ":502"
  ```
- Якщо слухає лише `127.0.0.1:502`, зробіть PortProxy:
  ```powershell
  netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=502 connectaddress=127.0.0.1 connectport=502
  ```

---

## 8. Типові проблеми та рішення

- **Grafana: `password authentication failed for user "grafana"`** — синхронізуйте пароль у БД та datasource:
  ```powershell
  docker exec -it timescaledb psql -U postgres -d telemetry -c "ALTER ROLE grafana WITH LOGIN PASSWORD 'grafana123';"
  ```
- **Telegraf: `unknown driver "postgres"`** — поставте `driver = "pgx"` у `outputs.sql`.
- **Telegraf: `cannot unmarshal TOML integer into []uint16`** — адреси **масивом**: `address = [0]`.
- **`connection refused 127.0.0.1:502`** — використовуйте `host.docker.internal:502` + правило фаєрвола.
- **`telemetry is not a view`** — перейменуйте таблицю `telemetry` або видаліть її перед створенням VIEW.

---

## 9. Міграція/перенесення на інший хост

### Варіант A — перенос папки (швидко, якщо архітектура/версії ті самі)
```powershell
docker compose stop telegraf grafana
docker compose stop timescaledb
Compress-Archive -Path .\* -DestinationPath ..\stack-backup.zip
# На цілі:
docker compose pull
docker compose up -d
```

### Варіант B — логічний бекап/відновлення БД
```powershell
# Джерело
docker compose stop telegraf
docker exec -t timescaledb pg_dump -U postgres -d telemetry -F c -f /tmp/telemetry.dump
docker cp timescaledb:/tmp/telemetry.dump .
# Ціль
docker compose up -d timescaledb
docker cp .	elemetry.dump timescaledb:/tmp/telemetry.dump
docker exec -it timescaledb psql -U postgres -d telemetry -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
docker exec -it timescaledb pg_restore -U postgres -d telemetry /tmp/telemetry.dump
```

### Варіант C — офлайн-перенос образів
```powershell
# Джерело
docker compose pull
docker save -o images.tar timescale/timescaledb:latest-pg16 grafana/grafana:10.4.4 telegraf:1.30 dpage/pgadmin4:8.12

# Ціль
docker load -i images.tar
docker compose up -d
```

---

## 10. Безпека та прод-хардінг

- Змінюйте всі дефолтні паролі; розгляньте Docker secrets.
- Фіксуйте версії образів, плануйте оновлення.
- Регулярні бекапи `pg_dump`; експортуйте дашборди Grafana в JSON або бекап `grafana.db`.
- Використовуйте VPN/фаєрвол, TLS до Postgres, розділення мереж.
- Для великих обсягів — політики retention/compression у Timescale, `continuous aggregates`.

---

## 11. Додатки

### A. Приклади SQL-запитів для Grafana/Excel

```sql
-- Сирі дані за вибраний період
SELECT ts AS "time", device_id, point, value
FROM telemetry
WHERE $__timeFilter(ts)
ORDER BY ts;

-- Годинні середні
SELECT t AS "time", avg_v AS value
FROM telemetry_1h
WHERE device_id = 'meter1'
  AND point = 'Voltage_L1'
  AND $__timeFilter(t)
ORDER BY t;

-- Pivot приклад (дві точки у стовпці)
SELECT t AS "time",
       AVG(CASE WHEN point='Voltage_L1' THEN avg_v END) AS voltage_l1,
       AVG(CASE WHEN point='Current_L1' THEN avg_v END) AS current_l1
FROM telemetry_1h
WHERE device_id = 'meter1'
  AND $__timeFilter(t)
GROUP BY t
ORDER BY t;
```

### B. Modbus RTU (COM-порт на Windows)

Якщо потрібен Modbus RTU всередині контейнера — користуйтеся перетворенням у TCP (serial-over-TCP).  
Або запускайте Telegraf **незадокереним** на хості для доступу до `COMx:`.

```toml
[[inputs.modbus]]
  name = "modbus_rtu"
  controller = "serial://COM3"
  baud_rate = 9600
  data_bits = 8
  parity = "N"
  stop_bits = 1
  slave_id = 1
  timeout = "2s"
  [[inputs.modbus.holding_registers]]
    name = "Flow"
    data_type = "UINT16"
    byte_order = "AB"
    scale = 0.1
    address = [0]
```

### C. XLSX-звіти (опційно через Metabase)

Grafana OSS надає експорт **CSV** (панель → Inspect → Download CSV).  
Для **.xlsx** і email-розсилок встановіть поруч **Metabase** і підключіть ту ж БД `telemetry`.

---

**Готово!** Якщо потрібні приклади під конкретний лічильник/PLC (карта регістрів) або стартовий дашборд Grafana — скажіть, додам.
