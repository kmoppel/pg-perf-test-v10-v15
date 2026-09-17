#!/bin/bash

set -e

PGHOST_TESTDB=127.0.0.1
PGPORT_TESTDB=6666
PGDATABASE_TESTDB=postgres
PGUSER_TESTDB=$USER
PGPASSWORD_TESTDB=postgres
CONNSTR_TESTDB="postgresql://${PGUSER_TESTDB}:${PGPASSWORD_TESTDB}@${PGHOST_TESTDB}:${PGPORT_TESTDB}/${PGDATABASE_TESTDB}?sslmode=disable"  # instances will be initialized
CONNSTR_RESULTSDB="postgresql://postgres@localhost:5432/resultsdb?sslmode=disable" # assumed existing and >= v13 for storing pg_stat_statement results from test instances
EXEC_ENV=local  # "aws" autodetected below

DUMMY_TEST_RUN=0  # If set use very small scale and TX counts just to verify that script is running OK / prereqs are met

# paths to Postgres installations to include into testing
declare -a BINDIRS
declare -a PGVER_MAJORS

BINDIRS+=("/usr/lib/postgresql/18/bin")
PGVER_MAJORS+=("18")
BINDIRS+=("/usr/lib/postgresql/19/bin")
#BINDIRS+=("/usr/local/pgsql_19beta3/bin")
PGVER_MAJORS+=("19")


PGBENCH=/usr/lib/postgresql/18/bin/pgbench

echo "Validating BINDIRS paths exist ..."
for BINDIR_CHECK in "${BINDIRS[@]}" ; do
  if [ ! -d "$BINDIR_CHECK" ]; then
    echo "ERROR: BINDIR '$BINDIR_CHECK' does not exist. Aborting." >&2
    exit 1
  fi
done


REMOVE_INSTANCES=1  # if set then 'rm -rf' each test instance DATADIR at end of test run (in case low on disk)
DATADIR=$HOME/pgbench_testset
mkdir -p $DATADIR
LOGDIR=./logs
mkdir -p $LOGDIR

PGBENCH_SCALES="800 1200" # In-mem vs light disk access (assuming 16GB RAM)
                          # scale 800 ~ 14 GB with FF80
                          # scale 1200 ~ 21 GB with FF80
#PGBENCH_SCALES="1200 2400"
PGBENCH_INIT_FLAGS="--foreign-keys -q --fillfactor 80"
PGBENCH_PROTOCOLS="simple prepared" # simple|extended|prepared
PGBENCH_PARTITIONS="0 32"
TEST_LOOPS=3 # To try to offset the effects of first pg version benefitting from a more better thermal / scaling / SSD trim situation
DISABLE_AUTOVACUUM=1 # To reduce randomness. Should combine with a bit of fillfactor in init flags to reduce write tx degradation for long test runs
CREATE_EXTRA_INDEX=1 # Create an additional index on pgbench_account (bid) to look a bit more "real life"
SLEEP_BETWEEN_RUNS=300 # To ease monitoring + possibly offset CPU "turbo" mode effects, favouring 1st tests

CPUS=`nproc`
PGBENCH_JOBS=1  # Should increase for heavy CPU count test nodes
if [ $CPUS -gt 8 ] ; then
  PGBENCH_JOBS=$(( CPUS/8 ))
fi

if curl -s -m 2 "http://169.254.169.254/latest/meta-data/instance-id" 2>/dev/null | grep -q "^i-"; then
  echo "Running on EC2"
  EXEC_ENV=aws
fi

declare -a QUERY_MODES
declare -a QUERY_FLAGS
declare -a CLIENTS # Aim to reduce parallel sessions for heavier queries that spawn workers, to avoid abnormal context switching
declare -a TRANSACTIONS # Use a fixed TX count as distorts overall picture less compared to time-based testing
                        # NB! Note TX are multiplied by clients


QUERY_MODES+=("select-only")
QUERY_FLAGS+=("--select-only")
if [ $PGBENCH_JOBS -gt 1 ] ; then
  CLIENTS+=("$((CPUS-PGBENCH_JOBS))")
else
  CLIENTS+=("$CPUS")
fi
TRANSACTIONS+=(4000000) # 5m

QUERY_MODES+=("select-only-batch")
QUERY_FLAGS+=("-f batch_read.sql")
CLIENTS+=("$((CPUS/2-PGBENCH_JOBS))")
TRANSACTIONS+=(1000000) # 1m

QUERY_MODES+=("full-scan")
QUERY_FLAGS+=("-f full_scan.sql")
CLIENTS+=("$((CPUS/2-PGBENCH_JOBS))")
TRANSACTIONS+=(1000) # 1k

QUERY_MODES+=("skip-some-updates")
QUERY_FLAGS+=("--skip-some-updates")
if [ $PGBENCH_JOBS -gt 1 ] ; then
  CLIENTS+=("$((CPUS-PGBENCH_JOBS))")
else
  CLIENTS+=("$CPUS")
fi
TRANSACTIONS+=(2000000) # 2m


if [ "$DUMMY_TEST_RUN" -gt 0 ]; then
  SLEEP_BETWEEN_RUNS=1
  PGBENCH_SCALES="1" # In-mem vs light disk access (assuming 16GB RAM)
                          # scale 800 ~ 14 GB with FF80
                          # scale 1200 ~ 21 GB with FF80
  PGBENCH_INIT_FLAGS="--foreign-keys -q --fillfactor 80 --unlogged"
  PGBENCH_PROTOCOLS="simple" # simple|extended|prepared
  PGBENCH_PARTITIONS="0"
  TEST_LOOPS=2 # To try to offset the effects of first pg version benefitting from a more better thermal / scaling / SSD trim situation
  TRANSACTIONS=()
  CLIENTS=()
  for q in "${QUERY_MODES[@]}" ; do
    TRANSACTIONS+=(10)  # PS results saving looks at queries >=10 calls!
    CLIENTS+=(1)
  done
  PGBENCH_JOBS=1
fi

echo "DUMMY_TEST_RUN $DUMMY_TEST_RUN"
echo "QUERY_MODES ${QUERY_MODES[@]}"
echo "QUERY_FLAGS ${QUERY_FLAGS[@]}"
echo "CLIENTS ${CLIENTS[@]}"
echo "TRANSACTIONS ${TRANSACTIONS[@]}"
echo "PROTOCOLS ${PGBENCH_PROTOCOLS[@]}"
echo "PGBENCH_JOBS ${PGBENCH_JOBS}"

# exit 0

SQL_PGSS_SETUP="CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA public;"
SQL_PGSS_RESULTSDB_SETUP="CREATE TABLE IF NOT EXISTS public.pgss_results AS SELECT ''::text AS exec_env, now() AS test_start_time, ''::text AS hostname, now() AS created_on, 0::int as loop_count, 0::numeric AS pgver, 0 as pgminor, 0 AS scale, 0 as partitions, 0 AS transactions, 0 AS clients, ''::text AS protocol, ''::text AS query_mode, mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, shared_blk_read_time, shared_blk_write_time, query FROM public.pg_stat_statements WHERE false;"
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


HOSTNAME=`hostname`
START_TIME=`date +%s`
START_TIME_PG=`psql "$CONNSTR_RESULTSDB" -qAXtc "select now();"`

echo "Ensuring pg_stat_statements extension on result server and public.pgss_results table ..."
exec_sql_resultsdb "$SQL_PGSS_SETUP"
exec_sql_resultsdb "$SQL_PGSS_RESULTSDB_SETUP"



##### TEST_LOOPS

loop_count=0
for loop_count in $(seq 1 $TEST_LOOPS) ; do
echo -e "\n\n##################### STARTING TEST LOOP $loop_count #####################\n\n"
LOOP_START_TIME=$(date +%s)

### Loop over all postgres versions, creating instances one by one, applying some PG config settings and starting

i=0
for BINDIR in "${BINDIRS[@]}" ; do
PGVER_MAJOR=${PGVER_MAJORS[i]}

echo -e "\n\n\n################ Initializing PGVER $PGVER_MAJOR ################\n"

if [ -e ${DATADIR}/pg${PGVER_MAJOR} ]; then
  echo "Cleaning possible prev state ..."
  set +e
  $BINDIR/pg_ctl --wait --log ${LOGDIR}/postgresql_${PGVER_MAJOR}.log -D ${DATADIR}/pg${PGVER_MAJOR} stop
  set -e
  rm -rf ${DATADIR}/pg${PGVER_MAJOR}
fi

echo "$BINDIR/initdb --auth=trust --data-checksums --username=$PGUSER_TESTDB $DATADIR/pg${PGVER_MAJOR}  >/dev/null"
$BINDIR/initdb --auth=trust --data-checksums --username=$PGUSER_TESTDB ${DATADIR}/pg${PGVER_MAJOR}  >/dev/null

cat postgresql.tune.${CPUS}-cpu.conf >> ${DATADIR}/pg${PGVER_MAJOR}/postgresql.conf
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

for PROTOCOL in $PGBENCH_PROTOCOLS ; do

echo -e "\n*** PROTOCOL $PROTOCOL ***\n"

echo "Creating test data using pgbench ..."
date
echo "pgbench -i -q $PGBENCH_INIT_FLAGS --partitions $PARTITIONS -s $SCALE \"$CONNSTR_TESTDB\" >/dev/null"
$PGBENCH -i -q $PGBENCH_INIT_FLAGS --partitions $PARTITIONS -s $SCALE "$CONNSTR_TESTDB" >/dev/null
echo "Init done. DB size:"
exec_sql "select pg_size_pretty(pg_database_size(current_database()))"

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
  echo "Creating an extra index on bid ..." # Try to be a bit more closer to real life
  echo "create index pgbench_accounts_bid_idx on pgbench_accounts(bid);"
  exec_sql "create index pgbench_accounts_bid_abalance_idx on pgbench_accounts(bid);"
fi


j=0
for QUERY_MODE in "${QUERY_MODES[@]}" ; do
  FLAGS=${QUERY_FLAGS[j]}
  PGBENCH_CLIENTS=${CLIENTS[j]}
  PGBENCH_TRANSACTIONS=${TRANSACTIONS[j]}

  echo -e "\n*** Testing query model: $QUERY_MODE with protocol $PROTOCOL ***\n"

  echo "VACUUM ANALYZE pgbench_accounts ..."
  exec_sql "VACUUM ANALYZE pgbench_accounts"

  echo "Reseting pg_stat_statements..."
  exec_sql "$SQL_PGSS_RESET" >/dev/null

  echo "Running the timed query test"
  echo "pgbench --random-seed 666 -n -P 30 -M $PROTOCOL -j $PGBENCH_JOBS -c $PGBENCH_CLIENTS -t $PGBENCH_TRANSACTIONS $FLAGS \"$CONNSTR_TESTDB\" &> $LOGDIR/pgbench_testset_pg_${SERVER_VERSION_NUM}_q_${QUERY_MODE}_c_${PGBENCH_CLIENTS}_s_${SCALE}_p_${PARTITIONS}_prot_${PROTOCOL}_loop_${loop_count}.log"
  $PGBENCH --random-seed 666 -n -P 30 -M $PROTOCOL -j $PGBENCH_JOBS -c $PGBENCH_CLIENTS -t $PGBENCH_TRANSACTIONS $FLAGS "$CONNSTR_TESTDB" &> $LOGDIR/pgbench_testset_pg_${SERVER_VERSION_NUM}_q_${QUERY_MODE}_c_${PGBENCH_CLIENTS}_s_${SCALE}_p_${PARTITIONS}_prot_${PROTOCOL}_loop_${loop_count}.log

  echo "Storing pg_stat_statements results into resultsdb public.pgss_results ..."

  echo "psql \"$CONNSTR_TESTDB\" -qXc \"copy (select '${EXEC_ENV}', '${START_TIME_PG}', '${HOSTNAME}', now(), $loop_count, ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PARTITIONS}, ${PGBENCH_TRANSACTIONS}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, shared_blk_read_time, shared_blk_write_time, query from public.pg_stat_statements where calls >= 10 and query ~* '(INSERT|UPDATE|SELECT).*pgbench') to stdout\" | psql \"$CONNSTR_RESULTSDB\" -qXc \"copy public.pgss_results from stdin\""
  psql "$CONNSTR_TESTDB" -qXc "copy (select '${EXEC_ENV}', '${START_TIME_PG}', '${HOSTNAME}', now(), $loop_count, ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PARTITIONS}, ${PGBENCH_TRANSACTIONS}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, shared_blk_read_time, shared_blk_write_time, query from public.pg_stat_statements where calls >= 10 and query ~* '(INSERT|UPDATE|SELECT).*pgbench') to stdout" | psql "$CONNSTR_RESULTSDB" -qXc "copy public.pgss_results from stdin"

  j=$((j+1))

  echo "Sleeping $SLEEP_BETWEEN_RUNS s before test start ..."
  sleep $SLEEP_BETWEEN_RUNS

echo "Done with QUERY_MODE $QUERY_MODE"
done # QUERY_MODE

echo "Done with PROTOCOL $PROTOCOL"
done # PGBENCH_PROTOCOLS

echo "Done with PARTITIONS $PARTITIONS"
done # PARTITIONS

echo "Done with SCALE $SCALE"
done # SCALE

echo "Storing DB and table stats to ${LOGDIR}/after_run_summary_v${PGVER_MAJOR}_scale_${SCALE}_q_${QUERY_MODE}_p_${PARTITIONS}_prot_${PROTOCOL}_loop_${loop_count}.log ..."
psql "$CONNSTR_TESTDB" -Xe -f after_run_get_summary.sql &> "${LOGDIR}/after_run_summary_v${PGVER_MAJOR}_scale_${SCALE}_q_${QUERY_MODE}_p_${PARTITIONS}_prot_${PROTOCOL}_loop_${loop_count}.log"

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

LOOP_END_TIME=$(date +%s)
echo -e "\nLOOP $loop_count DONE in $((LOOP_END_TIME-LOOP_START_TIME)) s\n"

done # LOOP_COUNT

END_TIME=`date +%s`
echo -e "\n\nSCRIPT DONE in $((END_TIME-START_TIME)) s"
