-- NUQ schema initialization for Firecrawl
-- Adapted from https://github.com/firecrawl/firecrawl/blob/main/apps/nuq-postgres/nuq.sql
-- pg_cron and ALTER SYSTEM tuning omitted (not available in postgres:16-alpine)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS nuq;

DO $$ BEGIN
  CREATE TYPE nuq.job_status AS ENUM ('queued', 'active', 'completed', 'failed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE nuq.group_status AS ENUM ('active', 'completed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS nuq.queue_scrape (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  status nuq.job_status DEFAULT 'queued',
  data jsonb,
  created_at timestamptz DEFAULT now(),
  priority int DEFAULT 0,
  lock uuid,
  locked_at timestamptz,
  stalls integer,
  finished_at timestamptz,
  listen_channel_id text,
  returnvalue jsonb,
  failedreason text,
  owner_id uuid,
  group_id uuid
);

CREATE TABLE IF NOT EXISTS nuq.queue_scrape_backlog (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  data jsonb,
  created_at timestamptz DEFAULT now(),
  priority int DEFAULT 0,
  listen_channel_id text,
  owner_id uuid,
  group_id uuid,
  times_out_at timestamptz
);

CREATE TABLE IF NOT EXISTS nuq.queue_crawl_finished (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  status nuq.job_status DEFAULT 'queued',
  data jsonb,
  created_at timestamptz DEFAULT now(),
  priority int DEFAULT 0,
  lock uuid,
  locked_at timestamptz,
  stalls integer,
  finished_at timestamptz,
  listen_channel_id text,
  returnvalue jsonb,
  failedreason text,
  owner_id uuid,
  group_id uuid
);

CREATE TABLE IF NOT EXISTS nuq.group_crawl (
  id uuid PRIMARY KEY,
  status nuq.group_status DEFAULT 'active',
  created_at timestamptz DEFAULT now(),
  owner_id uuid NOT NULL,
  ttl int8 DEFAULT 86400000,
  expires_at timestamptz
);

CREATE INDEX IF NOT EXISTS queue_scrape_active_locked_at_idx ON nuq.queue_scrape (locked_at) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS nuq_queue_scrape_queued_optimal_2_idx ON nuq.queue_scrape (priority, created_at, id) WHERE status = 'queued';
CREATE INDEX IF NOT EXISTS nuq_queue_scrape_failed_created_at_idx ON nuq.queue_scrape (created_at) WHERE status = 'failed';
CREATE INDEX IF NOT EXISTS nuq_queue_scrape_completed_created_at_idx ON nuq.queue_scrape (created_at) WHERE status = 'completed';
CREATE INDEX IF NOT EXISTS nuq_queue_scrape_group_owner_mode_idx ON nuq.queue_scrape (group_id, owner_id) WHERE data->>'mode' = 'single_urls';
CREATE INDEX IF NOT EXISTS nuq_queue_scrape_group_mode_status_idx ON nuq.queue_scrape (group_id, status) WHERE data->>'mode' = 'single_urls';
CREATE INDEX IF NOT EXISTS nuq_queue_scrape_group_completed_listing_idx ON nuq.queue_scrape (group_id, finished_at, created_at) WHERE status = 'completed' AND data->>'mode' = 'single_urls';
CREATE INDEX IF NOT EXISTS idx_queue_scrape_group_status ON nuq.queue_scrape (group_id, status) WHERE status IN ('active', 'queued');
CREATE INDEX IF NOT EXISTS nuq_queue_scrape_backlog_owner_id_idx ON nuq.queue_scrape_backlog (owner_id);
CREATE INDEX IF NOT EXISTS nuq_queue_scrape_backlog_group_mode_idx ON nuq.queue_scrape_backlog (group_id) WHERE data->>'mode' = 'single_urls';
CREATE INDEX IF NOT EXISTS idx_queue_scrape_backlog_group_id ON nuq.queue_scrape_backlog (group_id);
CREATE INDEX IF NOT EXISTS queue_crawl_finished_active_locked_at_idx ON nuq.queue_crawl_finished (locked_at) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS nuq_queue_crawl_finished_queued_optimal_2_idx ON nuq.queue_crawl_finished (priority, created_at, id) WHERE status = 'queued';
CREATE INDEX IF NOT EXISTS nuq_queue_crawl_finished_failed_created_at_idx ON nuq.queue_crawl_finished (created_at) WHERE status = 'failed';
CREATE INDEX IF NOT EXISTS nuq_queue_crawl_finished_completed_created_at_idx ON nuq.queue_crawl_finished (created_at) WHERE status = 'completed';
CREATE INDEX IF NOT EXISTS idx_group_crawl_status ON nuq.group_crawl (status) WHERE status = 'active';
