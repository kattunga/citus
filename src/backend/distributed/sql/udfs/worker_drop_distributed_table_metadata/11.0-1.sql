DROP FUNCTION IF EXISTS pg_catalog.worker_drop_distributed_table_metadata(table_name text);

CREATE OR REPLACE FUNCTION pg_catalog.worker_drop_distributed_table_metadata(table_name text)
    RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_drop_distributed_table_metadata$$;

COMMENT ON FUNCTION pg_catalog.worker_drop_distributed_table_metadata(table_name text)
    IS 'drop the distributed table's reference from metadata tables';

