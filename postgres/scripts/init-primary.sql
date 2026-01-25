-- =============================================================================
-- Primary Database Initialization Script
-- Creates users, enables extensions, and sets up replication
-- =============================================================================

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- -----------------------------------------------------------------------------
-- Create replication user (for streaming replication)
-- Uses certificate authentication (no password needed, but REPLICATION privilege required)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
        CREATE ROLE replicator WITH REPLICATION LOGIN;
        RAISE NOTICE 'Created replicator role';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- Create application user with cert auth (CN=appuser)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'appuser') THEN
        CREATE ROLE appuser WITH LOGIN;
        RAISE NOTICE 'Created appuser role';
    END IF;
END
$$;

-- Grant appuser access to default database
GRANT CONNECT ON DATABASE postgres TO appuser;
GRANT USAGE ON SCHEMA public TO appuser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appuser;

-- -----------------------------------------------------------------------------
-- Create password-authenticated user (for testing password auth)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'pwduser') THEN
        CREATE ROLE pwduser WITH LOGIN PASSWORD 'pwduser_secret';
        RAISE NOTICE 'Created pwduser role';
    END IF;
END
$$;

GRANT CONNECT ON DATABASE postgres TO pwduser;
GRANT USAGE ON SCHEMA public TO pwduser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO pwduser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO pwduser;

-- -----------------------------------------------------------------------------
-- Create a replication slot for the replica (optional but good practice)
-- This ensures WAL segments are retained even if replica is temporarily down
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'replica_slot') THEN
        PERFORM pg_create_physical_replication_slot('replica_slot');
        RAISE NOTICE 'Created replication slot: replica_slot';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- Create a sample table with vector column for testing pgvector
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS test_vectors (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(3),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert sample data
INSERT INTO test_vectors (content, embedding) VALUES
    ('Hello World', '[1,2,3]'),
    ('PostgreSQL rocks', '[4,5,6]'),
    ('pgvector is awesome', '[7,8,9]')
ON CONFLICT DO NOTHING;

RAISE NOTICE 'Primary initialization complete!';
