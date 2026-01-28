-- =============================================================================
-- Primary Database Initialization Script
-- Creates users, enables extensions, and sets up replication
-- =============================================================================

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- -----------------------------------------------------------------------------
-- Create replication user with password from environment
-- Password is set via ALTER ROLE since CREATE ROLE doesn't support env vars
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
        CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'changeme';
        RAISE NOTICE 'Created replicator role (password should be changed via ALTER ROLE)';
    END IF;
END
$$;

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
