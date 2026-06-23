-- HealthFlow Sunbird RC - Database Initialization Script
-- Creates required databases and extensions for all services

-- Create databases for each service.
-- PostgreSQL has no "CREATE DATABASE IF NOT EXISTS"; emulate it with \gexec.
-- "registry" is already created by the POSTGRES_DB env var, so it is skipped.
SELECT 'CREATE DATABASE keycloak'          WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'keycloak')\gexec
SELECT 'CREATE DATABASE identity'          WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'identity')\gexec
SELECT 'CREATE DATABASE credential_schema' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'credential_schema')\gexec
SELECT 'CREATE DATABASE credentials'       WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'credentials')\gexec
SELECT 'CREATE DATABASE claims'            WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'claims')\gexec
SELECT 'CREATE DATABASE idgen'             WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'idgen')\gexec
SELECT 'CREATE DATABASE bulk_issuance'     WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bulk_issuance')\gexec

-- Grant privileges to healthflow user
GRANT ALL PRIVILEGES ON DATABASE registry TO healthflow;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO healthflow;
GRANT ALL PRIVILEGES ON DATABASE identity TO healthflow;
GRANT ALL PRIVILEGES ON DATABASE credential_schema TO healthflow;
GRANT ALL PRIVILEGES ON DATABASE credentials TO healthflow;
GRANT ALL PRIVILEGES ON DATABASE claims TO healthflow;
GRANT ALL PRIVILEGES ON DATABASE idgen TO healthflow;
GRANT ALL PRIVILEGES ON DATABASE bulk_issuance TO healthflow;

-- Connect to registry database and create extensions
\c registry;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create audit table for registry events
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    entity_type VARCHAR(100) NOT NULL,
    entity_id VARCHAR(255) NOT NULL,
    action VARCHAR(50) NOT NULL,
    actor_id VARCHAR(255),
    actor_type VARCHAR(50),
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    old_value JSONB,
    new_value JSONB,
    metadata JSONB
);

CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_timestamp ON audit_log(timestamp);
CREATE INDEX idx_audit_actor ON audit_log(actor_id);

-- Create ID sequence tables for Egyptian healthcare IDs
CREATE TABLE IF NOT EXISTS id_sequences (
    id_type VARCHAR(50) PRIMARY KEY,
    current_value BIGINT DEFAULT 0,
    prefix VARCHAR(20),
    suffix VARCHAR(20),
    year_prefix BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert initial sequences for HealthFlow ID formats
INSERT INTO id_sequences (id_type, prefix, year_prefix) VALUES
    ('doctor', 'EG-DR-', true),
    ('pharmacist', 'EG-PH-', true),
    ('nurse', 'EG-NR-', true),
    ('facility', 'EG-FAC-', true),
    ('license', 'EG-LIC-', true)
ON CONFLICT (id_type) DO NOTHING;

-- Connect to identity database
\c identity;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Connect to credentials database
\c credentials;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Connect to claims database
\c claims;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Connect to bulk_issuance database
\c bulk_issuance;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create bulk issuance job tracking table
CREATE TABLE IF NOT EXISTS bulk_jobs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    schema_name VARCHAR(100) NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    total_records INTEGER DEFAULT 0,
    processed_records INTEGER DEFAULT 0,
    success_count INTEGER DEFAULT 0,
    error_count INTEGER DEFAULT 0,
    status VARCHAR(50) DEFAULT 'pending',
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_by VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    error_report_url TEXT,
    success_report_url TEXT,
    metadata JSONB
);

CREATE INDEX idx_bulk_jobs_status ON bulk_jobs(status);
CREATE INDEX idx_bulk_jobs_schema ON bulk_jobs(schema_name);
CREATE INDEX idx_bulk_jobs_created ON bulk_jobs(created_at);

-- Create bulk issuance error log table
CREATE TABLE IF NOT EXISTS bulk_errors (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    job_id UUID REFERENCES bulk_jobs(id),
    row_number INTEGER,
    error_type VARCHAR(100),
    error_message TEXT,
    original_data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_bulk_errors_job ON bulk_errors(job_id);

COMMENT ON DATABASE registry IS 'HealthFlow Sunbird RC - Main Registry Database';
COMMENT ON DATABASE identity IS 'HealthFlow Sunbird RC - DID Identity Service Database';
COMMENT ON DATABASE credentials IS 'HealthFlow Sunbird RC - Verifiable Credentials Database';
COMMENT ON DATABASE claims IS 'HealthFlow Sunbird RC - Claims/Attestation Database';
COMMENT ON DATABASE bulk_issuance IS 'HealthFlow Sunbird RC - Bulk Issuance Service Database';
