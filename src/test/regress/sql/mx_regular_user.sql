CREATE SCHEMA "Mx Regular User";
SET search_path TO "Mx Regular User";

-- add coordinator in idempotent way
SELECT 1 FROM master_add_node('localhost', :master_port, groupid => 0);

-- create a role and give access one each node separately
-- and increase the error level to prevent enterprise to diverge
SET client_min_messages TO ERROR;
CREATE USER regular_mx_user WITH LOGIN;
SELECT 1 FROM run_command_on_workers($$CREATE USER regular_mx_user WITH LOGIN;$$);
GRANT ALL ON SCHEMA "Mx Regular User" TO regular_mx_user;

-- create another table owned by the super user (e.g., current user of the session)
-- and GRANT access to the user
CREATE SCHEMA "Mx Super User";
SELECT 1 FROM run_command_on_workers($$CREATE SCHEMA "Mx Super User";$$);
SET citus.next_shard_id TO 2980000;
SET citus.next_placement_id TO 2980000;
SET search_path TO "Mx Super User";
CREATE TABLE super_user_owned_regular_user_granted (a int PRIMARY KEY, b int);
SELECT create_reference_table ('"Mx Super User".super_user_owned_regular_user_granted');

-- show that this table is owned by super user
SELECT
	rolsuper
FROM
	pg_roles
		WHERE oid
			IN
		(SELECT relowner FROM pg_class WHERE oid = '"Mx Super User".super_user_owned_regular_user_granted'::regclass);

-- make sure that granting produce the same output for both community and enterprise
SET client_min_messages TO ERROR;
GRANT USAGE ON SCHEMA "Mx Super User" TO regular_mx_user;
GRANT INSERT ON TABLE super_user_owned_regular_user_granted TO regular_mx_user;

SELECT 1 FROM run_command_on_workers($$GRANT USAGE ON SCHEMA "Mx Super User" TO regular_mx_user;$$);
SELECT 1 FROM run_command_on_workers($$GRANT INSERT ON TABLE "Mx Super User".super_user_owned_regular_user_granted TO regular_mx_user;$$);
SELECT 1 FROM run_command_on_placements('super_user_owned_regular_user_granted', $$GRANT INSERT ON TABLE %s TO regular_mx_user;$$);

-- now that the GRANT is given, the regular user should be able to
-- INSERT into the table
\c - regular_mx_user - :master_port
SET search_path TO "Mx Super User";
COPY super_user_owned_regular_user_granted FROM STDIN WITH CSV;
1,1
2,1
\.

-- however, this specific user doesn't have UPDATE/UPSERT/DELETE/TRUNCATE
-- permission, so  should fail
INSERT INTO super_user_owned_regular_user_granted VALUES (1, 1), (2, 1) ON CONFLICT (a) DO NOTHING;
TRUNCATE super_user_owned_regular_user_granted;
DELETE FROM super_user_owned_regular_user_granted;
UPDATE super_user_owned_regular_user_granted SET a = 1;

-- AccessExclusiveLock == 8 is strictly forbidden for any user
SELECT lock_shard_resources(8, ARRAY[2980000]);

-- ExclusiveLock == 7 is forbidden for this user
-- as only has INSERT rights
SELECT lock_shard_resources(7, ARRAY[2980000]);

-- but should be able to acquire RowExclusiveLock
BEGIN;
	SELECT count(*) > 0 as acquired_lock from pg_locks where pid = pg_backend_pid() AND locktype = 'advisory';
	SELECT lock_shard_resources(3, ARRAY[2980000]);
	SELECT count(*) > 0 as acquired_lock from pg_locks where pid = pg_backend_pid() AND locktype = 'advisory';
COMMIT;

-- acquring locks on non-existing shards is not meaningful but still we do not throw error as we might be in the middle
-- of metadata syncing. We just do not acquire the locks
BEGIN;
	SELECT count(*) > 0 as acquired_lock from pg_locks where pid = pg_backend_pid() AND locktype = 'advisory';
	SELECT lock_shard_resources(3, ARRAY[123456871]);
	SELECT count(*) > 0 as acquired_lock from pg_locks where pid = pg_backend_pid() AND locktype = 'advisory';
COMMIT;


\c - postgres - :master_port;
SET search_path TO "Mx Super User";
SET client_min_messages TO ERROR;

-- now allow users to do UPDATE on the tables
GRANT UPDATE ON TABLE super_user_owned_regular_user_granted TO regular_mx_user;
SELECT 1 FROM run_command_on_workers($$GRANT UPDATE ON TABLE "Mx Super User".super_user_owned_regular_user_granted TO regular_mx_user;$$);
SELECT 1 FROM run_command_on_placements('super_user_owned_regular_user_granted', $$GRANT UPDATE ON TABLE %s TO regular_mx_user;$$);

\c - regular_mx_user - :master_port
SET search_path TO "Mx Super User";

UPDATE super_user_owned_regular_user_granted SET b = 1;

-- AccessExclusiveLock == 8 is strictly forbidden for any user
-- even after UPDATE is allowed
SELECT lock_shard_resources(8, ARRAY[2980000]);

\c - postgres - :master_port;
SET client_min_messages TO ERROR;
DROP SCHEMA "Mx Super User" CASCADE;

\c - postgres - :worker_1_port;
SET client_min_messages TO ERROR;
SET citus.enable_ddl_propagation TO OFF;
CREATE SCHEMA "Mx Regular User";
GRANT ALL ON SCHEMA "Mx Regular User" TO regular_mx_user;

\c - postgres - :worker_2_port;
SET client_min_messages TO ERROR;
SET citus.enable_ddl_propagation TO OFF;
CREATE SCHEMA "Mx Regular User";
GRANT ALL ON SCHEMA "Mx Regular User" TO regular_mx_user;

-- now connect with that user
\c - regular_mx_user - :master_port
SET search_path TO "Mx Regular User";
SET citus.next_shard_id TO 1560000;
SET citus.next_placement_id TO 1560000;

-- make sure that we sync the metadata
SET citus.shard_replication_factor TO 1;

CREATE TABLE partitioned_table (long_column_names_1 int, long_column_names_2 int, long_column_names_3 int, long_column_names_4 int, long_column_names_5 int, long_column_names_6 int, long_column_names_7 int, long_column_names_8 int, long_column_names_9 int, long_column_names_10 int, long_column_names_11 timestamp) PARTITION BY RANGE (long_column_names_11);
CREATE TABLE very_long_child_partition_name_is_required_to_repro_the_bug PARTITION OF partitioned_table FOR VALUES FROM ('2011-01-01') TO ('2012-01-01');

SELECT create_distributed_table('partitioned_table', 'long_column_names_1');
SELECT bool_and(hasmetadata) FROM pg_dist_node WHERE nodename = 'localhost' and nodeport IN (:worker_1_port, :worker_2_port);

-- show that we can rollback
BEGIN;
	CREATE INDEX long_index_on_parent_table ON partitioned_table (long_column_names_1, long_column_names_2, long_column_names_3, long_column_names_4, long_column_names_5, long_column_names_6, long_column_names_11) INCLUDE (long_column_names_7, long_column_names_7, long_column_names_9, long_column_names_10);
ROLLBACK;

-- show that we can switch to sequential mode and still
-- sync the metadata to the nodes
BEGIN;
	CREATE INDEX long_index_on_parent_table ON partitioned_table (long_column_names_1, long_column_names_2, long_column_names_3, long_column_names_4, long_column_names_5, long_column_names_6, long_column_names_11) INCLUDE (long_column_names_7, long_column_names_7, long_column_names_9, long_column_names_10);
	show citus.multi_shard_modify_mode;
COMMIT;

-- make sure that partitioned tables, columnar and conversion to columnar workes fine
-- on Citus MX with a non-super user
CREATE SEQUENCE my_mx_seq;
CREATE TABLE users_table_part(col_to_drop int, user_id int, value_1 int, value_2 bigint DEFAULT nextval('my_mx_seq'::regclass), value_3 bigserial) PARTITION BY RANGE (value_1);
CREATE TABLE users_table_part_0 PARTITION OF users_table_part FOR VALUES FROM (0) TO (1);
CREATE TABLE users_table_part_1 PARTITION OF users_table_part FOR VALUES FROM (1) TO (2);
SELECT create_distributed_table('users_table_part', 'user_id', colocate_with:='partitioned_table');

-- make sure that we can handle dropped columns nicely
ALTER TABLE users_table_part DROP COLUMN col_to_drop;

INSERT INTO users_table_part SELECT i, i %2, i %50 FROM generate_series(0, 100) i;

BEGIN;
	-- make sure to use multiple connections
	SET LOCAL citus.force_max_query_parallelization TO ON;

	CREATE TABLE users_table_part_2 PARTITION OF users_table_part FOR VALUES FROM (2) TO (3);
	INSERT INTO users_table_part SELECT i, i %3, i %50 FROM generate_series(0, 100) i;

	CREATE TABLE users_table_part_3 (user_id int, value_1 int, value_2 bigint, value_3 bigserial);
	ALTER TABLE users_table_part ATTACH PARTITION users_table_part_3 FOR VALUES FROM (3) TO (4);
	CREATE TABLE users_table_part_4 PARTITION OF users_table_part FOR VALUES FROM (4) TO (5) USING COLUMNAR;;
COMMIT;

SELECT alter_table_set_access_method('users_table_part_0', 'columnar');
SELECT alter_table_set_access_method('users_table_part_0', 'heap');

BEGIN;
	SET LOCAL citus.force_max_query_parallelization TO ON;
	SELECT alter_table_set_access_method('users_table_part_0', 'columnar');
	SELECT alter_table_set_access_method('users_table_part_0', 'heap');
ROLLBACK;

BEGIN;
	SET LOCAL citus.force_max_query_parallelization TO ON;
	SELECT undistribute_table('users_table_part');
	SELECT create_distributed_table('users_table_part', 'user_id');
COMMIT;

BEGIN;
	-- make sure to use multiple connections
	SET LOCAL citus.force_max_query_parallelization TO ON;
	SELECT alter_distributed_table('users_table_part', shard_count:=9, cascade_to_colocated:=false);
ROLLBACK;

BEGIN;
	-- make sure to use multiple connections
	SET LOCAL citus.force_max_query_parallelization TO ON;
	ALTER TABLE users_table_part ADD COLUMN my_column INT DEFAULT 15;
	CREATE INDEX test_index ON users_table_part(value_3, value_2);
	CREATE INDEX test_index_on_child ON users_table_part_3(value_3, value_2);
ROLLBACK;

CREATE TABLE local_table_in_the_metadata (id int PRIMARY KEY, value_1 int);

CREATE TABLE reference_table(id int PRIMARY KEY, value_1 int);
SELECT create_reference_table('reference_table');

CREATE TABLE on_delete_fkey_table(id int PRIMARY KEY, value_1 int);
SELECT create_distributed_table('on_delete_fkey_table', 'id', colocate_with:='partitioned_table');
ALTER TABLE reference_table ADD CONSTRAINT fkey_to_local FOREIGN KEY(id) REFERENCES local_table_in_the_metadata(id);
ALTER TABLE on_delete_fkey_table ADD CONSTRAINT veerrrrrrryyy_veerrrrrrryyy_veerrrrrrryyy_long_constraint_name FOREIGN KEY(value_1) REFERENCES reference_table(id) ON DELETE CASCADE;
INSERT INTO local_table_in_the_metadata SELECT i, i FROM generate_series(0, 100) i;
INSERT INTO reference_table SELECT i, i FROM generate_series(0, 100) i;
INSERT INTO on_delete_fkey_table SELECT i, i % 100  FROM generate_series(0, 1000) i;

-- make sure that we can handle switching to sequential execution nicely
-- on MX with a regular user
BEGIN;
	DELETE FROM reference_table WHERE id > 50;
	SHOW citus.multi_shard_modify_mode;
	ALTER TABLE on_delete_fkey_table ADD COLUMN t int DEFAULT 10;
	SELECT avg(t) FROM on_delete_fkey_table;
ROLLBACK;

-- make sure to use multiple connections per node
SET citus.force_max_query_parallelization TO ON;
CREATE INDEX CONCURRENTLY concurrent_index_test ON on_delete_fkey_table(id);
CREATE UNIQUE INDEX unique_key_example ON on_delete_fkey_table(id, value_1);

BEGIN;
	TRUNCATE local_table_in_the_metadata, reference_table, on_delete_fkey_table;
	SELECT count(*) FROM local_table_in_the_metadata;
	SELECT count(*) FROM reference_table;
	SELECT count(*) FROM on_delete_fkey_table;
ROLLBACK;

BEGIN;
	SET citus.multi_shard_modify_mode TO 'sequential';
	TRUNCATE on_delete_fkey_table CASCADE;
	TRUNCATE reference_table CASCADE;
	SELECT count(*) FROM local_table_in_the_metadata JOIN reference_table USING(id) JOIN on_delete_fkey_table USING(id);
ROLLBACK;

-- join involving local, reference and distributed tables
SELECT count(*) FROM local_table_in_the_metadata JOIN reference_table USING(id) JOIN on_delete_fkey_table USING(id);

-- query with intermediate results
WITH cte_1 AS (SELECT * FROM on_delete_fkey_table ORDER BY 1,2 DESC LIMIT 10)
	SELECT count(*) FROM cte_1;

-- query with intermediate results on remote nodes
WITH cte_1 AS (SELECT * FROM on_delete_fkey_table ORDER BY 1,2 DESC LIMIT 10)
	SELECT count(*) FROM cte_1 JOIN on_delete_fkey_table USING(value_1);

-- repartition joins
SET citus.enable_repartition_joins to ON;
SELECT count(*) FROM on_delete_fkey_table o1 JOIN on_delete_fkey_table o2 USING(value_1);

-- repartition INSERT .. SELECT
INSERT INTO on_delete_fkey_table (id, value_1) SELECT value_1, id FROM on_delete_fkey_table ON CONFLICT DO NOTHING;

-- make sure that we can create a type and use it in the same tx
BEGIN;
	CREATE TYPE test_type AS (a int, b int);
	CREATE TABLE composite_key (id int PRIMARY KEY, c int, data test_type);
	SELECT create_distributed_table('composite_key', 'id', colocate_with:='partitioned_table');
COMMIT;

-- index statistics should work fine
CREATE INDEX test_index_on_parent ON users_table_part((value_3+value_2));
ALTER INDEX test_index_on_parent ALTER COLUMN 1 SET STATISTICS 4646;
DROP INDEX test_index_on_parent;

ALTER TABLE composite_key ALTER COLUMN c TYPE float USING (b::float + 0.5);

-- make sure that rebalancer works fine with a regular user on MX
-- first make sure that we can rollback
BEGIN;
	SELECT citus_move_shard_placement(1560000, 'localhost', :worker_1_port, 'localhost', :worker_2_port, 'block_writes');
ROLLBACK;

SELECT citus_move_shard_placement(1560000, 'localhost', :worker_1_port, 'localhost', :worker_2_port, 'block_writes');

-- connect to the worker to see if the table has the correct owned and placement metadata
\c - postgres - :worker_2_port
SELECT
	1560000, groupid = (SELECT groupid FROM pg_dist_node WHERE nodeport = :worker_2_port AND nodename = 'localhost' AND isactive)
FROM
	pg_dist_placement
WHERE
	shardid = 1560000;

-- also make sure that pg_dist_shard_placement is updated correctly
SELECT
	nodeport = :worker_2_port
FROM pg_dist_shard_placement WHERE shardid = 1560000;

\c - postgres - :worker_1_port
SELECT
	1560000, groupid = (SELECT groupid FROM pg_dist_node WHERE nodeport = :worker_2_port AND nodename = 'localhost' AND isactive)
FROM
	pg_dist_placement
WHERE
	shardid = 1560000;

-- also make sure that pg_dist_shard_placement is updated correctly
SELECT
	nodeport = :worker_2_port
FROM pg_dist_shard_placement WHERE shardid = 1560000;

-- now connect with the user to the coordinator again
\c - regular_mx_user - :master_port
SET search_path TO "Mx Regular User";

-- make sure that we can still execute queries
SELECT count(*) FROM local_table_in_the_metadata JOIN reference_table USING(id) JOIN on_delete_fkey_table USING(id);

-- now, call directly the rebalancer, which should also work fine
SELECT rebalance_table_shards(shard_transfer_mode:='block_writes');
-- make sure that we can still execute queries
SELECT count(*) FROM local_table_in_the_metadata JOIN reference_table USING(id) JOIN on_delete_fkey_table USING(id);

-- lets run some queries from the workers
\c - regular_mx_user - :worker_2_port
SET search_path TO "Mx Regular User";
SELECT count(*) FROM local_table_in_the_metadata JOIN reference_table USING(id) JOIN on_delete_fkey_table USING(id);
BEGIN;
	TRUNCATE reference_table CASCADE;
ROLLBACK;

-- join involving local, reference and distributed tables
SELECT count(*) FROM local_table_in_the_metadata JOIN reference_table USING(id) JOIN on_delete_fkey_table USING(id);

-- query with intermediate results
WITH cte_1 AS (SELECT * FROM on_delete_fkey_table ORDER BY 1,2 DESC LIMIT 10)
	SELECT count(*) FROM cte_1;

-- query with intermediate results on remote nodes
WITH cte_1 AS (SELECT * FROM on_delete_fkey_table ORDER BY 1,2 DESC LIMIT 10)
	SELECT count(*) FROM cte_1 JOIN on_delete_fkey_table USING(value_1);

-- repartition joins
SET citus.enable_repartition_joins to ON;
SELECT count(*) FROM on_delete_fkey_table o1 JOIN on_delete_fkey_table o2 USING(value_1);

BEGIN;
	SET LOCAL citus.force_max_query_parallelization TO ON;
	DELETE FROM on_delete_fkey_table;
	WITH cte_1 AS (SELECT * FROM on_delete_fkey_table ORDER BY 1,2 DESC LIMIT 10)
	SELECT count(*) FROM cte_1;
COMMIT;

\c - postgres - :master_port

-- resync the metadata to both nodes for test purposes and then stop
SELECT start_metadata_sync_to_node('localhost', :worker_1_port);
SELECT start_metadata_sync_to_node('localhost', :worker_2_port);

SELECT stop_metadata_sync_to_node('localhost', :worker_1_port);
SELECT stop_metadata_sync_to_node('localhost', :worker_2_port);

-- finally sync metadata again so it doesn't break later tests
SELECT start_metadata_sync_to_node('localhost', :worker_1_port);
SELECT start_metadata_sync_to_node('localhost', :worker_2_port);

DROP SCHEMA "Mx Regular User" CASCADE;
