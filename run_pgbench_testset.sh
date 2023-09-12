#!/bin/bash

set -e

PGHOST_TESTDB=127.0.0.1
PGPORT_TESTDB=6666
PGDATABASE_TESTDB=postgres
PGUSER_TESTDB=$USER
PGPASSWORD_TESTDB=postgres
CONNSTR_TESTDB="postgresql://${PGUSER_TESTDB}:${PGPASSWORD_TESTDB}@${PGHOST_TESTDB}:${PGPORT_TESTDB}/${PGDATABASE_TESTDB}"  # instances will be initialized
CONNSTR_RESULTSDB="postgresql://postgres@localhost:5431/resultsdb" # assumed existing and >= v13 for storing pg_stat_statement results from test instances
EXEC_ENV=local

# paths to Postgres installations to include into testing
declare -a BINDIRS
declare -a PGVER_MAJORS

BINDIRS+=("/usr/lib/postgresql/15/bin")
PGVER_MAJORS+=("15")
BINDIRS+=("/usr/lib/postgresql/16/bin")
PGVER_MAJORS+=("16")


PGBENCH=/usr/lib/postgresql/15/bin/pgbench


REMOVE_INSTANCES=0  # if 1 then 'rm -rf' each test instance DATADIR before the next major version (in case low on disk)
DATADIR=$HOME/pgbench_testset
mkdir -p $DATADIR
LOGDIR=${DATADIR}/logs
mkdir -p $LOGDIR

PGBENCH_SCALES="1000 5000" # In-mem vs light disk access (assuming 16GB RAM)
PGBENCH_SCALES="500 2500" # In-mem vs light disk access (assuming 16GB RAM)
PGBENCH_INIT_FLAGS="--foreign-keys -q --fillfactor 85"
PGBENCH_CLIENTS=4 # For localhost testing no point to set higher than CPUs
PGBENCH_JOBS=1
PGBENCH_DURATION=7200
PGBENCH_CACHE_WARMUP_DURATION=60 # Do some random reads before each test
PROTOCOL="simple" # simple|extended|prepared
PGBENCH_PARTITIONS="0 16"
DISABLE_AUTOVACUUM=1 # To reduce randomness. Should combine with a bit of fillfactor in init flags to reduce write tx degradation for long test runs
CREATE_EXTRA_INDEX=1 # Create an additional index on pgbench_account (bid, abalance) to look a bit more "real life"

declare -a QUERY_MODES
declare -a QUERY_FLAGS
declare -a CLIENTS_DIVISOR # Increase for heavier queries to reduce the client count / parallel load. clients = PGBENCH_CLIENTS / divisor

QUERY_MODES+=("select-only")
QUERY_FLAGS+=("--select-only")
CLIENTS_DIVISOR+=(1)
QUERY_MODES+=("select-only-batch")
QUERY_FLAGS+=("-f batch_read.sql")
CLIENTS_DIVISOR+=(2)
QUERY_MODES+=("full-scan")
QUERY_FLAGS+=("-f full_scan.sql")
CLIENTS_DIVISOR+=(2)
QUERY_MODES+=("skip-some-updates")
QUERY_FLAGS+=("--skip-some-updates")
CLIENTS_DIVISOR+=(1)
QUERY_MODES+=("skip-some-updates-batch")
QUERY_FLAGS+=("-f batch_update.sql")
CLIENTS_DIVISOR+=(2)

SQL_PGSS_SETUP="CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA public;"
SQL_PGSS_RESULTSDB_SETUP="CREATE TABLE IF NOT EXISTS public.pgss_results AS SELECT ''::text AS exec_env, now() AS test_start_time, ''::text AS hostname, now() AS created_on, 0::numeric AS pgver, 0 as pgminor, 0 AS scale, 0 AS duration, 0 AS clients, ''::text AS protocol, ''::text AS query_mode, mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query FROM public.pg_stat_statements WHERE false;"
SQL_PGSS_RESET="SELECT public.pg_stat_statements_reset();"
SQL_PGSTATS_RESET="SELECT pg_stat_reset();"
SQL_DISABLE_AUTOVACUUM_PART=$(cat <<- "EOF"
DO $$
DECLARE
r record;
BEGIN
  FOR r IN (
    select format('alter table %s set (autovacuum_enabled = off)', relid::regclass) sql from pg_stat_user_tables where relname ~ '^pgbench_accounts\_'
  ) LOOP
    RAISE WARNING '%', r.sql ;
    EXECUTE r.sql ;
  END LOOP;
END;
$$;
EOF
)

function exec_sql() {
    psql "$CONNSTR_TESTDB" -Xqc "$1"
}

function exec_sql_resultsdb() {
    psql "$CONNSTR_RESULTSDB" -Xqc "$1"
}

if [ "$REMOVE_INSTANCES" -gt 0 ]; then
  rm -rf $DATADIR/pg*
fi

HOSTNAME=`hostname`
START_TIME=`date +%s`
START_TIME_PG=`psql "$CONNSTR_RESULTSDB" -qAXtc "select now();"`

echo "Ensuring pg_stat_statements extension on result server and public.pgss_results table ..."
exec_sql_resultsdb "$SQL_PGSS_SETUP"
exec_sql_resultsdb "$SQL_PGSS_RESULTSDB_SETUP"


### Loop over all postgres versions, creating instances one by one, applying some PG config settings and starting

i=0
for BINDIR in "${BINDIRS[@]}" ; do
PGVER_MAJOR=${PGVER_MAJORS[i]}

echo -e "\n\n\n################ Initializing PGVER $PGVER_MAJOR ################\n"

echo "$BINDIR/initdb --auth=trust --data-checksums --username=$PGUSER_TESTDB $DATADIR/pg${PGVER_MAJOR}  >/dev/null"
$BINDIR/initdb --auth=trust --data-checksums --username=$PGUSER_TESTDB ${DATADIR}/pg${PGVER_MAJOR}  >/dev/null

cat postgresql.tune.conf >> ${DATADIR}/pg${PGVER_MAJOR}/postgresql.conf
echo "port=${PGPORT_TESTDB}" >> ${DATADIR}/pg${PGVER_MAJOR}/postgresql.conf

echo "$BINDIR/pg_ctl --wait --log ${LOGDIR}/postgresql_${PGVER_MAJOR}.log -D ${DATADIR}/pg${PGVER_MAJOR} start"
$BINDIR/pg_ctl --wait --log ${LOGDIR}/postgresql_${PGVER_MAJOR}.log -D ${DATADIR}/pg${PGVER_MAJOR} start

if [ "$PGDATABASE_TESTDB" != "postgres" ]; then
  $BINDIR/createdb "$PGDATABASE_TESTDB"
fi

SERVER_VERSION_NUM=`psql "$CONNSTR_TESTDB" -qAXtc "show server_version_num"`
echo "Connection OK, SERVER_VERSION_NUM $SERVER_VERSION_NUM"

echo "Ensuring pg_stat_statements extension on test instance ..."
exec_sql "$SQL_PGSS_SETUP"

echo "Starting the test loop ..."


for SCALE in $PGBENCH_SCALES ; do

echo -e "\n*** SCALE $SCALE ***\n"

for PARTITIONS in $PGBENCH_PARTITIONS ; do

echo -e "\n*** PARTITIONS $PARTITIONS ***\n"

echo "Creating test data using pgbench ..."
date
echo "pgbench -i -q $PGBENCH_INIT_FLAGS --partitions $PARTITIONS -s $SCALE \"$CONNSTR_TESTDB\" >/dev/null"
$PGBENCH -i -q $PGBENCH_INIT_FLAGS --partitions $PARTITIONS -s $SCALE "$CONNSTR_TESTDB" >/dev/null

if [ "$DISABLE_AUTOVACUUM" -gt 0 ]; then
    echo -e "\nDisabling Autovacuum / Autoanalyze on pgbench_accounts ..."
    if [ "$PARTITIONS" -gt 0 ]; then
      psql -X "$CONNSTR_TESTDB" -c "$SQL_DISABLE_AUTOVACUUM_PART"
    else
      psql -X "$CONNSTR_TESTDB" -c "alter table public.pgbench_accounts set (autovacuum_enabled = off)"
    fi
fi
date

if [ "$CREATE_EXTRA_INDEX" -gt 0 ]; then
  echo "Creating an extra index on (bid, abalance)..." # Try to be more close to real life
  echo "create index pgbench_accounts_bid_abalance_idx on pgbench_accounts(bid, abalance);"
  exec_sql "create index pgbench_accounts_bid_abalance_idx on pgbench_accounts(bid, abalance);"
fi

echo "Reseting pg_stats..."
exec_sql "$SQL_PGSTATS_RESET" >/dev/null

j=0
for QUERY_MODE in "${QUERY_MODES[@]}" ; do
  FLAGS=${QUERY_FLAGS[j]}
  EFFECTIVE_CLIENTS=$((PGBENCH_CLIENTS / CLIENTS_DIVISOR[j]))
  if [ "$EFFECTIVE_CLIENTS" -eq 0 ]; then
    EFFECTIVE_CLIENTS=1
  fi

  echo -e "\n*** Testing query model: $QUERY_MODE with protocol $PROTOCOL ***\n"

  echo "Doing cache warmup for $PGBENCH_CACHE_WARMUP_DURATION seconds..."
  echo "pgbench -S -j $PGBENCH_JOBS -c $PGBENCH_CLIENTS -T $PGBENCH_CACHE_WARMUP_DURATION \"$CONNSTR_TESTDB\" >/dev/null"
  $PGBENCH -S -j $PGBENCH_JOBS -c $PGBENCH_CLIENTS -T $PGBENCH_CACHE_WARMUP_DURATION "$CONNSTR_TESTDB" >/dev/null

  echo "Reseting pg_stat_statements..."
  exec_sql "$SQL_PGSS_RESET" >/dev/null

  echo "Running the timed query test"
  echo "pgbench --random-seed 666 -M $PROTOCOL -j $PGBENCH_JOBS -c $PGBENCH_CLIENTS -T $PGBENCH_DURATION $FLAGS \"$CONNSTR_TESTDB\" &> /tmp/pgbench_testset_pg_${SERVER_VERSION_NUM}_q_${QUERY_MODE}_c_${PGBENCH_CLIENTS}_s_${SCALE}_p_${PARTITIONS}.log"
  $PGBENCH --random-seed 666 -M $PROTOCOL -j $PGBENCH_JOBS -c $PGBENCH_CLIENTS -T $PGBENCH_DURATION $FLAGS "$CONNSTR_TESTDB" &> /tmp/pgbench_testset_pg_${SERVER_VERSION_NUM}_q_${QUERY_MODE}_c_${PGBENCH_CLIENTS}_s_${SCALE}_p_${PARTITIONS}.log

  echo "Storing pg_stat_statements results into resultsdb public.pgss_results ..."

  if [ "$SERVER_VERSION_NUM" -ge "130000" ] ; then
    echo "psql \"$CONNSTR_TESTDB\" -qXc \"copy (select '${EXEC_ENV}', '${START_TIME_PG}', '${HOSTNAME}', now(), ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PGBENCH_DURATION}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query from public.pg_stat_statements where calls > 10 and query ~* '(INSERT|UPDATE|SELECT).*pgbench') to stdout\" | psql \"$CONNSTR_RESULTSDB\" -qXc \"copy public.pgss_results from stdin\""
    psql "$CONNSTR_TESTDB" -qXc "copy (select '${EXEC_ENV}', '${START_TIME_PG}', '${HOSTNAME}', now(), ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PGBENCH_DURATION}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query from public.pg_stat_statements where calls > 10 and query ~* '(INSERT|UPDATE|SELECT).*pgbench') to stdout" | psql "$CONNSTR_RESULTSDB" -qXc "copy public.pgss_results from stdin"
  else
    echo "psql \"$CONNSTR_TESTDB\" -qXc \"copy (select '${EXEC_ENV}', '${START_TIME_PG}', '${HOSTNAME}', now(), ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PGBENCH_DURATION}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_time, stddev_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query from public.pg_stat_statements where calls > 10 and query ~* '(INSERT|UPDATE|SELECT).*pgbench') to stdout\" | psql \"$CONNSTR_RESULTSDB\" -qXc \"copy public.pgss_results from stdin\""
    psql "$CONNSTR_TESTDB" -qXc "copy (select '${EXEC_ENV}', '${START_TIME_PG}', '${HOSTNAME}', now(), ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PGBENCH_DURATION}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_time, stddev_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query from public.pg_stat_statements where calls > 10 and query ~* '(INSERT|UPDATE|SELECT).*pgbench') to stdout" | psql "$CONNSTR_RESULTSDB" -qXc "copy public.pgss_results from stdin"
  fi

  j=$((j+1))

echo "Done with QUERY_MODE $QUERY_MODE"
done # QUERY_MODE

echo "Done with PARTITIONS $PARTITIONS"
done # PARTITIONS

echo "Done with SCALE $SCALE"
done # SCALE

echo "Storing DB and table stats to ${LOGDIR}/after_run_summary_v${PGVER_MAJOR}_scale_${SCALE}_q_${QUERY_MODE}.log ..."
psql "$CONNSTR_TESTDB" -Xe -f after_run_get_summary.sql &> "${LOGDIR}/after_run_summary_v${PGVER_MAJOR}_scale_${SCALE}_q_${QUERY_MODE}.log"

echo "$BINDIR/pg_ctl --wait -t 300 -D ${DATADIR}/pg${PGVER_MAJOR} stop"
$BINDIR/pg_ctl --wait -t 300 -D ${DATADIR}/pg${PGVER_MAJOR} stop

i=$((i+1))

if [ "$REMOVE_INSTANCES" -gt 0 ]; then
  if [ $i -lt ${#BINDIRS[@]} ]; then # Leave the last one for possible debug
    echo "Removing instance $PGVER_MAJOR ..."
    rm -rf ${DATADIR}/pg${PGVER_MAJOR}
  fi
fi

done # BINDIR

END_TIME=`date +%s`
echo -e "\nDONE in $((END_TIME-START_TIME)) s"
