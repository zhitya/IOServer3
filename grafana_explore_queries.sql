-- Прості запити для Grafana Explore (TimescaleDB)

-- 1. Підрахунок всіх записів
SELECT COUNT(*) as total_records FROM telemetry;

-- 2. Список всіх таблиць (для перевірки доступу)
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';

-- 3. Список всіх представлень
SELECT table_name FROM information_schema.views WHERE table_schema = 'public';

-- 4. Останні 5 записів
SELECT * FROM telemetry ORDER BY ts DESC LIMIT 5;

-- 5. Унікальні пристрої
SELECT DISTINCT device_id FROM telemetry;

-- 6. Унікальні точки вимірювання
SELECT DISTINCT point FROM telemetry;

-- 7. Дані за останню годину
SELECT ts, device_id, point, value 
FROM telemetry 
WHERE ts > NOW() - INTERVAL '1 hour'
ORDER BY ts;

-- 8. Простий запит з часом (для графіків)
SELECT ts as time, value 
FROM telemetry 
WHERE device_id = 'sensor1' AND point = 'value'
ORDER BY ts;
