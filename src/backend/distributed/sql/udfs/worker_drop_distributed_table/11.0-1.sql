DROP FUNCTION IF EXISTS pg_catalog.worker_drop_distributed_table(table_name text);

CREATE OR REPLACE FUNCTION pg_catalog.worker_drop_distributed_table(table_name text, drop_sequences bool DEFAULT true)
    RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_drop_distributed_table$$;

COMMENT ON FUNCTION pg_catalog.worker_drop_distributed_table(table_name text, drop_sequences bool)
    IS 'drop the distributed table and its reference from metadata tables';

