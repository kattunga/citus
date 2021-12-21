CREATE OR REPLACE FUNCTION pg_catalog.enable_citus_mx_for_pre_citus11()
  RETURNS SETOF regclass
  LANGUAGE plpgsql
  AS $$
DECLARE
        partitioned_table_count_pre_11 int:=0;
BEGIN

    SELECT 
      metadata->'partitioned_table_count_pre_11' INTO partitioned_table_count_pre_11 
    FROM pg_dist_node_metadata;

    IF partitioned_table_count_pre_11 IS NOT NULL AND partitioned_table_count_pre_11 > 0 THEN

     -- first, fix the partitions
     SELECT pg_catalog.fix_all_partition_shard_index_names();

     UPDATE pg_dist_node_metadata 
     SET metadata=jsonb_set(metadata, '{partitioned_table_count_pre_11}', to_jsonb(partitioned_table_count), true);
    END IF;


    -- TODO: replace this with activate node when Burak merges the PR
    -- TODO: parallelize this across nodes
    SELECT 
      start_metadata_sync_to_node(nodename,nodeport) 
    FROM 
      pg_dist_node WHERE isactive AND noderole = 'primary' AND NOT hasmetadata;

  RETURN;
END;
$$;
COMMENT ON FUNCTION pg_catalog.enable_citus_mx()
  IS 'enables citus MX';
