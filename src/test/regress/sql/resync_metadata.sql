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
SET client_min_messages TO ERROR;
DROP SCHEMA resync_metadata CASCADE;
