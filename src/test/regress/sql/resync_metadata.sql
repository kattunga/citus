CREATE SCHEMA resync_metadata;
SET search_path TO resync_metadata;

CREATE TABLE test_serial(a bigserial PRIMARY KEY);
SELECT create_distributed_table('test_serial', 'a');

CREATE SEQUENCE myseq;
CREATE TABLE test_sequence(a bigint DEFAULT nextval('myseq'));
SELECT create_distributed_table('test_sequence', 'a');

\c - - - :worker_1_port
SET search_path tO resync_metadata;

INSERT INTO test_serial VALUES(DEFAULT) RETURNING *;
INSERT INTO test_serial VALUES(DEFAULT) RETURNING *;

INSERT into test_sequence VALUES(DEFAULT) RETURNING *;
INSERT into test_sequence VALUES(DEFAULT) RETURNING *;

\c - - - :master_port
SELECT start_metadata_sync_to_node('localhost', :worker_1_port);


\c - - - :worker_1_port
SET search_path tO resync_metadata;

-- can continue inserting with the existing sequence/serial
INSERT INTO test_serial VALUES(DEFAULT) RETURNING *;
INSERT INTO test_serial VALUES(DEFAULT) RETURNING *;

INSERT into test_sequence VALUES(DEFAULT) RETURNING *;
INSERT into test_sequence VALUES(DEFAULT) RETURNING *;

\c - - - :master_port
SET search_path tO resync_metadata;

DROP TABLE test_serial, test_sequence;

\c - - - :worker_1_port
SET search_path tO resync_metadata;

-- show that we only have the sequences left after
-- dropping the tables (e.g., bigserial is dropped)
select count(*) from pg_sequences where schemaname ilike '%resync_metadata%';

\c - - - :master_port
SET client_min_messages TO ERROR;
DROP SCHEMA resync_metadata CASCADE;
