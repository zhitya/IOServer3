-- Приклади SQL запитів для використання в Grafana

-- 1. Простий запит для отримання всіх точок даних з часом
SELECT 
    ts as time,
    device_id,
    point,
    value
FROM telemetry 
ORDER BY ts DESC;

-- 2. Температурні дані з часом (для графіків)
SELECT 
    ts as time,
    device_id,
    value as "Temperature"
FROM telemetry 
WHERE point = 'value' AND device_id = 'sensor1'
ORDER BY ts;

-- 3. Вологість з часом
SELECT 
    ts as time,
    device_id,
    value as "Humidity"
FROM telemetry 
WHERE point = 'humidity' AND device_id = 'sensor1'
ORDER BY ts;

-- 4. Тиск з часом
SELECT 
    ts as time,
    device_id,
    value as "Pressure"
FROM telemetry 
WHERE point = 'value' AND device_id = 'sensor2'
ORDER BY ts;

-- 5. Всі дані за останню годину
SELECT 
    ts as time,
    device_id,
    point as "Metric",
    value
FROM telemetry 
WHERE ts > NOW() - INTERVAL '1 hour'
ORDER BY ts DESC;

-- 6. Середні значення за останню годину (для stat panels)
SELECT 
    AVG(value) as "Average Value",
    MAX(value) as "Max Value",
    MIN(value) as "Min Value"
FROM telemetry 
WHERE point = 'value' 
    AND device_id = 'sensor1' 
    AND ts > NOW() - INTERVAL '1 hour';

-- 7. Кількість записів по пристроях
SELECT 
    device_id,
    COUNT(*) as "Record Count"
FROM telemetry 
WHERE ts > NOW() - INTERVAL '1 hour'
GROUP BY device_id;
