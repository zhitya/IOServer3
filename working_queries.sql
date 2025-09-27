-- Працюючі SQL запити для Grafana

-- 1. Простий запит - підрахунок записів
SELECT COUNT(*) as count FROM telemetry;

-- 2. Останні 10 записів з часом
SELECT 
    ts as time,
    device_id,
    point,
    value
FROM telemetry 
ORDER BY ts DESC 
LIMIT 10;

-- 3. Температурні дані sensor1
SELECT 
    ts as time,
    value
FROM telemetry 
WHERE device_id = 'sensor1' AND point = 'value'
ORDER BY ts;

-- 4. Вологість sensor1
SELECT 
    ts as time,
    value
FROM telemetry 
WHERE device_id = 'sensor1' AND point = 'humidity'
ORDER BY ts;

-- 5. Тиск sensor2
SELECT 
    ts as time,
    value
FROM telemetry 
WHERE device_id = 'sensor2' AND point = 'value'
ORDER BY ts;

-- 6. Всі дані за останню годину
SELECT 
    ts as time,
    device_id,
    point,
    value
FROM telemetry 
WHERE ts > NOW() - INTERVAL '1 hour'
ORDER BY ts;

-- 7. Середнє значення за останню годину
SELECT 
    AVG(value) as avg_value
FROM telemetry 
WHERE ts > NOW() - INTERVAL '1 hour';

-- 8. Дані по пристроях
SELECT 
    device_id,
    COUNT(*) as record_count
FROM telemetry 
GROUP BY device_id;
