CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_object_metadata(
							typeText text,
                            objNames text[],
                            objArgs text[],
							distribution_argument_index int,
                            colocationid int)
    RETURNS void
    LANGUAGE C
    STRICT
    AS 'MODULE_PATHNAME';

COMMENT ON FUNCTION pg_catalog.citus_internal_add_object_metadata(text,text[],text[],int,int) IS
    'Inserts distributed object into pg_dist_object';
