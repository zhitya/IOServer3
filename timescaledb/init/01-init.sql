-- TimescaleDB Initialization Script
-- This script sets up the database schema, users, and optimizations

-- Create TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create main metrics table
CREATE TABLE IF NOT EXISTS public.metrics (
    time timestamptz NOT NULL,
    measurement text NOT NULL,
    tags jsonb,
    fields jsonb
);

-- Convert to hypertable for time-series optimization
SELECT create_hypertable('public.metrics', 'time', if_not_exists => TRUE);

-- Create telemetry view for easier querying
CREATE OR REPLACE VIEW public.telemetry AS
SELECT 
    time AS ts,
    COALESCE(tags->>'device_id', tags->>'name', 'unknown') AS device_id,
    key AS point,
    (fields->>key)::double precision AS value
FROM public.metrics 
CROSS JOIN LATERAL jsonb_object_keys(fields) AS key;

-- Create continuous aggregate for hourly data
CREATE MATERIALIZED VIEW IF NOT EXISTS public.telemetry_1h 
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 hour', time) AS t,
    COALESCE(tags->>'device_id', tags->>'name', 'unknown') AS device_id,
    key AS point,
    avg((fields->>key)::double precision) AS avg_v,
    min((fields->>key)::double precision) AS min_v,
    max((fields->>key)::double precision) AS max_v,
    count(*) AS count
FROM public.metrics 
CROSS JOIN LATERAL jsonb_object_keys(fields) AS key
GROUP BY 1, 2, 3;

-- Add continuous aggregate policy
SELECT add_continuous_aggregate_policy(
    'public.telemetry_1h',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour'
);

-- Create daily aggregate for long-term storage
CREATE MATERIALIZED VIEW IF NOT EXISTS public.telemetry_1d 
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 day', time) AS t,
    COALESCE(tags->>'device_id', tags->>'name', 'unknown') AS device_id,
    key AS point,
    avg((fields->>key)::double precision) AS avg_v,
    min((fields->>key)::double precision) AS min_v,
    max((fields->>key)::double precision) AS max_v,
    count(*) AS count
FROM public.metrics 
CROSS JOIN LATERAL jsonb_object_keys(fields) AS key
GROUP BY 1, 2, 3;

-- Add daily aggregate policy
SELECT add_continuous_aggregate_policy(
    'public.telemetry_1d',
    start_offset => INTERVAL '30 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day'
);

-- Create users and set permissions
-- Note: Passwords should be set via environment variables in production
-- For local development, using default passwords is acceptable
DO $$
BEGIN
    -- Create telegraf user
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'telegraf') THEN
        CREATE ROLE telegraf LOGIN PASSWORD 'telegraf123';
    END IF;
    
    -- Create grafana user
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'grafana') THEN
        CREATE ROLE grafana LOGIN PASSWORD 'grafana123';
    END IF;
    
    -- Create readonly user for reports
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'reports') THEN
        CREATE ROLE reports LOGIN PASSWORD 'reports123';
    END IF;
END
$$;

-- Grant permissions
GRANT USAGE ON SCHEMA public TO telegraf, grafana, reports;
GRANT INSERT, SELECT ON public.metrics TO telegraf;
GRANT SELECT ON public.metrics, public.telemetry, public.telemetry_1h, public.telemetry_1d TO grafana, reports;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_metrics_time_measurement ON public.metrics (time DESC, measurement);
CREATE INDEX IF NOT EXISTS idx_metrics_tags ON public.metrics USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_telemetry_1h_time ON public.telemetry_1h (t DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_1d_time ON public.telemetry_1d (t DESC);

-- Add compression policy for old data
SELECT add_compression_policy('public.metrics', INTERVAL '7 days');

-- Add retention policy (keep raw data for 30 days, hourly for 1 year, daily for 5 years)
SELECT add_retention_policy('public.metrics', INTERVAL '30 days');
SELECT add_retention_policy('public.telemetry_1h', INTERVAL '1 year');
SELECT add_retention_policy('public.telemetry_1d', INTERVAL '5 years');

-- Create device registry table
CREATE TABLE IF NOT EXISTS public.devices (
    id SERIAL PRIMARY KEY,
    device_id TEXT UNIQUE NOT NULL,
    name TEXT,
    protocol TEXT DEFAULT 'modbus',
    connection_params JSONB,
    register_map JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create alerts table
CREATE TABLE IF NOT EXISTS public.alerts (
    id SERIAL PRIMARY KEY,
    device_id TEXT NOT NULL,
    point TEXT NOT NULL,
    threshold_value DOUBLE PRECISION,
    threshold_type TEXT CHECK (threshold_type IN ('gt', 'lt', 'eq', 'ne')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Grant permissions on new tables
GRANT SELECT ON public.devices, public.alerts TO grafana, reports;
GRANT ALL ON public.devices, public.alerts TO telegraf;

-- Create function to update device updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_devices_updated_at 
    BEFORE UPDATE ON public.devices 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();