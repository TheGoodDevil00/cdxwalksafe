-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Nodes: Represents intersections or points of interest
CREATE TABLE IF NOT EXISTS nodes (
    id BIGSERIAL PRIMARY KEY,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    osm_id BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_nodes_location ON nodes USING GIST(location);

-- Edges: Pedestrian pathways with risk attributes
CREATE TABLE IF NOT EXISTS edges (
    id BIGSERIAL PRIMARY KEY,
    source_node BIGINT REFERENCES nodes(id),
    target_node BIGINT REFERENCES nodes(id),
    geometry GEOGRAPHY(LINESTRING, 4326) NOT NULL,
    distance_meters FLOAT GENERATED ALWAYS AS (ST_Length(geometry)) STORED,
    
    -- Risk Factors
    base_risk_score FLOAT DEFAULT 0.0,
    lighting_score FLOAT DEFAULT 0.5,
    terrain_type TEXT,
    
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_edges_geometry ON edges USING GIST(geometry);

-- Canonical incident report table used by risk scoring and user submissions.
CREATE TABLE IF NOT EXISTS incident_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_hash TEXT NOT NULL,
    incident_type TEXT NOT NULL,
    description TEXT,
    severity SMALLINT NOT NULL DEFAULT 3,
    status TEXT NOT NULL DEFAULT 'pending',
    confidence_score NUMERIC(5,2) NOT NULL DEFAULT 0.50,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    location GEOGRAPHY(POINT, 4326) GENERATED ALWAYS AS (
        ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
    ) STORED,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    verified_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_incident_reports_location
    ON incident_reports USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_incident_reports_created_at
    ON incident_reports (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_incident_reports_status
    ON incident_reports (status);

-- Canonical emergency table used by SOS flow and alert auditing.
CREATE TABLE IF NOT EXISTS emergency_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_hash TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    location GEOGRAPHY(POINT, 4326) GENERATED ALWAYS AS (
        ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
    ) STORED,
    status TEXT NOT NULL DEFAULT 'triggered',
    message TEXT,
    contacts_notified INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_emergency_alerts_location
    ON emergency_alerts USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_emergency_alerts_created_at
    ON emergency_alerts (created_at DESC);

-- Users (Ephemeral)
CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    user_hash TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
