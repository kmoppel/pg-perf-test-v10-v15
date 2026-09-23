#!/bin/bash

set -e

PGHOST_TESTDB=127.0.0.1
PGPORT_TESTDB=6666
PGDATABASE_TESTDB=postgres
PGUSER_TESTDB=$USER
PGPASSWORD_TESTDB=postgres
CONNSTR_TESTDB="postgresql://${PGUSER_TESTDB}:${PGPASSWORD_TESTDB}@${PGHOST_TESTDB}:${PGPORT_TESTDB}/${PGDATABASE_TESTDB}?sslmode=disable"  # instances will be initialized
CONNSTR_RESULTSDB="postgresql://postgres@localhost:5432/resultsdb?sslmode=disable" # assumed existing and >= v13 for storing pg_stat_statement results from test instances
CONNSTR_RESULTSDB="postgresql://peakasutaja:Andmebaasiv6ti@resultsdb.cbmgyiu4sv5w.eu-north-1.rds.amazonaws.com:5432/resultsdb?sslmode=require" # assumed existing and >= v13 for storing pg_stat_statement results from test instances
EXEC_ENV=local  # "aws" autodetected below

DUMMY_TEST_RUN=0  # If set use very small scale and TX counts just to verify that script is running OK / prereqs are met

# paths to Postgres installations to include into testing
declare -a BINDIRS
declare -a PGVER_MAJORS

BINDIRS+=("/usr/lib/postgresql/18/bin")
PGVER_MAJORS+=("18")
BINDIRS+=("/usr/lib/postgresql/18/bin")
#BINDIRS+=("/usr/local/pgsql_19beta3/bin")
PGVER_MAJORS+=("20")


PGBENCH=/usr/lib/postgresql/18/bin/pgbench

echo "Validating BINDIRS paths exist ..."
for BINDIR_CHECK in "${BINDIRS[@]}" ; do
  if [ ! -d "$BINDIR_CHECK" ]; then
    echo "ERROR: BINDIR '$BINDIR_CHECK' does not exist. Aborting." >&2
    exit 1
  fi
done


DATADIR=$HOME/pgbench_testset
mkdir -p $DATADIR
LOGDIR_ROOT=./logs
if [ ! -d ./logs ]; then
  mkdir -p $LOGDIR_ROOT
fi

PGBENCH_SCALES="1000 2500" # In-mem vs light disk access (assuming 16GB RAM)
                          # scale 800 ~ 14 GB with FF80
                          # scale 1200 ~ 21 GB with FF80
                          # NB! Need double the space on test host + some space for table / index growth
#PGBENCH_SCALES="1200 2400"
PGBENCH_INIT_FLAGS="--foreign-keys -q --fillfactor 80"
PGBENCH_PROTOCOLS="prepared" # simple|extended|prepared
PGBENCH_PARTITIONS="0"
TEST_LOOPS=1 # To try to offset the effects of first pg version benefitting from a more better thermal / scaling / SSD trim situation
DISABLE_AUTOVACUUM=1 # To reduce randomness. Should combine with a bit of fillfactor in init flags to reduce write tx degradation for long test runs
CREATE_EXTRA_INDEX=1 # Create an additional index on pgbench_account (bid) to look a bit more "real life"
SLEEP_BETWEEN_RUNS=300 # To ease monitoring + possibly offset CPU "turbo" mode effects, favouring 1st tests

CPUS=`nproc`
CPUS=16
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
declare -a IS_MUTATING  # To re-init pgbench only when there have been changes. Mutating tests should be declared after read-only ones


QUERY_MODES+=("select-only")
QUERY_FLAGS+=("--select-only")
if [ $PGBENCH_JOBS -gt 1 ] ; then
  CLIENTS+=("$((CPUS-PGBENCH_JOBS-1))")
else
  CLIENTS+=("$CPUS")
fi
TRANSACTIONS+=(10000000) # 10m
IS_MUTATING+=(0)  # Only re-init data if mutated

QUERY_MODES+=("select-only-batch")
QUERY_FLAGS+=("-f batch_read.sql")
CLIENTS+=("$((CPUS/2-PGBENCH_JOBS))")
TRANSACTIONS+=(1000000) # 1m
IS_MUTATING+=(0)  # Only re-init data if mutated
#
#QUERY_MODES+=("full-scan")
#QUERY_FLAGS+=("-f full_scan.sql")
#CLIENTS+=("$((CPUS/2-PGBENCH_JOBS))")
#TRANSACTIONS+=(1000) # 1k
#IS_MUTATING+=(0)

QUERY_MODES+=("skip-some-updates")
QUERY_FLAGS+=("--skip-some-updates")
if [ $PGBENCH_JOBS -gt 1 ] ; then
  CLIENTS+=("$((CPUS-PGBENCH_JOBS-1))")
else
  CLIENTS+=("$CPUS")
fi
TRANSACTIONS+=(2000000) # 2m
IS_MUTATING+=(1)  # Only re-init data if mutated


if [ "$DUMMY_TEST_RUN" -gt 0 ]; then
  SLEEP_BETWEEN_RUNS=3
  PGBENCH_SCALES="1 2"
  PGBENCH_INIT_FLAGS="--foreign-keys -q --fillfactor 80 --unlogged"
  PGBENCH_PROTOCOLS="simple prepared" # simple|extended|prepared
  PGBENCH_PARTITIONS="0 2"
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
echo "IS_MUTATING ${IS_MUTATING[@]}"
echo "PROTOCOLS ${PGBENCH_PROTOCOLS[@]}"
echo "PGBENCH_JOBS ${PGBENCH_JOBS}"
echo "TEST_LOOPS ${TEST_LOOPS}"

# exit 0

SQL_PGSS_SETUP="CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA public;"
SQL_PGSS_RESULTSDB_SETUP="CREATE TABLE IF NOT EXISTS public.pgss_results AS SELECT ''::text AS exec_env, now() AS test_start_time, ''::text AS hostname, now() AS created_on, 0::int as loop_count, 0::int as loop_dur, 0::numeric AS pgver, 0 as pgminor, 0 AS scale, 0 as partitions, 0 AS transactions, 0 AS clients, ''::text AS protocol, ''::text AS query_mode, mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, query FROM public.pg_stat_statements WHERE false;"
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
    psql "$CONNSTR_TESTDB" -XAtqc "$1"
}

function exec_sql_resultsdb() {
    psql "$CONNSTR_RESULTSDB" -Xqc "$1"
}


echo "Cleaning up possible leftover instances from prev runs"
set +e
i=0
for BINDIR in "${BINDIRS[@]}" ; do
  PGVER_MAJOR=${PGVER_MAJORS[i]}
  if [ -e "${DATADIR}/pg${PGVER_MAJOR}/postmaster.pid" ]; then
    echo "Stopping / cleaning up ${DATADIR}/pg${PGVER_MAJOR} ..."
    $BINDIR/pg_ctl --wait -D ${DATADIR}/pg${PGVER_MAJOR} stop -m i
    rm -rf ${DATADIR}/pg${PGVER_MAJOR}
  fi
  i=$((i+1))
done
set -e


HOSTNAME=`hostname`
TESTSET_START_TIME=`date +%s`
TESTSET_START_TIME_PG=`psql "$CONNSTR_RESULTSDB" -qAXtc "select now();"`
LOGDIR=${LOGDIR_ROOT}/run_start_${TESTSET_START_TIME}
mkdir $LOGDIR

echo "Ensuring pg_stat_statements extension on result server and public.pgss_results table ..."
exec_sql_resultsdb "$SQL_PGSS_SETUP"
exec_sql_resultsdb "$SQL_PGSS_RESULTSDB_SETUP"



##### TEST_LOOPS

loop_count=0
for loop_count in $(seq 1 $TEST_LOOPS) ; do
echo -e "\n\n##################### STARTING TEST LOOP $loop_count #####################\n\n"
LOOP_START_TIME=$(date +%s)

for SCALE in $PGBENCH_SCALES ; do

echo -e "\n*** SCALE $SCALE ***\n"

for PARTITIONS in $PGBENCH_PARTITIONS ; do

echo -e "\n*** PARTITIONS $PARTITIONS ***\n"

for PROTOCOL in $PGBENCH_PROTOCOLS ; do

echo -e "\n*** PROTOCOL $PROTOCOL ***\n"

declare -A has_pgver_been_mutated

for PGVER in "${PGVER_MAJORS[@]}" ; do
    has_pgver_been_mutated+=(["$PGVER"]=0)
done


pgver_index=0
for BINDIR in "${BINDIRS[@]}" ; do
  PGVER_MAJOR="${PGVER_MAJORS[pgver_index]}"
  echo -e "\n*** BINDIR $BINDIR ***\n"

  if [ ! -d "$DATADIR/pg${PGVER_MAJOR}" ]; then
    echo -e "\n\n\n################ Initializing a new PGVER $PGVER_MAJOR instance ################\n"
    echo "$BINDIR/initdb --auth=trust --data-checksums --username=$PGUSER_TESTDB $DATADIR/pg${PGVER_MAJOR}  >/dev/null"
    $BINDIR/initdb --auth=trust --data-checksums --username=$PGUSER_TESTDB ${DATADIR}/pg${PGVER_MAJOR}  >/dev/null

    cat postgresql.tune.${CPUS}-cpu.conf >> ${DATADIR}/pg${PGVER_MAJOR}/postgresql.conf
    echo "port=${PGPORT_TESTDB}" >> ${DATADIR}/pg${PGVER_MAJOR}/postgresql.conf
  fi

  echo "$BINDIR/pg_ctl --wait --log ${LOGDIR}/postgresql_${PGVER_MAJOR}.log -D ${DATADIR}/pg${PGVER_MAJOR} start"
  $BINDIR/pg_ctl --wait --log ${LOGDIR}/postgresql_${PGVER_MAJOR}.log -D ${DATADIR}/pg${PGVER_MAJOR} start

  if [ "$PGDATABASE_TESTDB" != "postgres" ]; then
    $BINDIR/createdb "$PGDATABASE_TESTDB" 2>/dev/null || true
  fi

  SERVER_VERSION_NUM=`psql "$CONNSTR_TESTDB" -qAXtc "show server_version_num"`
  echo "Connection OK, SERVER_VERSION_NUM $SERVER_VERSION_NUM"

  echo "Ensuring pg_stat_statements extension on test instance ..."
  exec_sql "$SQL_PGSS_SETUP"

  query_mode_index=0
  for QUERY_MODE in "${QUERY_MODES[@]}" ; do
    FLAGS=${QUERY_FLAGS[query_mode_index]}
    PGBENCH_CLIENTS=${CLIENTS[query_mode_index]}
    PGBENCH_TRANSACTIONS=${TRANSACTIONS[query_mode_index]}

    is_mutated="${has_pgver_been_mutated[$PGVER_MAJOR]}"
    if [ "$query_mode_index" -eq 0 ] || [ "$is_mutated" -gt 0 ]; then
      echo -e "\n#### Generating fresh test data using pgbench for PGVER $PGVER_MAJOR QUERY_MODE $QUERY_MODE ####\n"
      date
      echo "pgbench --initialize -q $PGBENCH_INIT_FLAGS --partitions $PARTITIONS -s $SCALE \"$CONNSTR_TESTDB\" >/dev/null"
      $PGBENCH --initialize -q $PGBENCH_INIT_FLAGS --partitions $PARTITIONS -s $SCALE "$CONNSTR_TESTDB" >/dev/null
      DB_SIZE=$(exec_sql "select pg_size_pretty(pg_database_size(current_database()))")
      echo "Init done. DB size: $DB_SIZE"

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
    else
      echo "Reusing existing test data for PGVER $PGVER_MAJOR as not yet mutated ..."
    fi

    echo "VACUUM ANALYZE pgbench_accounts ..."
    exec_sql "VACUUM ANALYZE pgbench_accounts"

    echo "Sleeping $SLEEP_BETWEEN_RUNS s before test start ..."
    sleep $SLEEP_BETWEEN_RUNS

    echo "Reseting pg_stat_statements..."
    exec_sql "$SQL_PGSS_RESET" >/dev/null

    echo -e "\n*** Testing query model: $QUERY_MODE with Postgres $PGVER_MAJOR protocol $PROTOCOL partitions $PARTITIONS scale $SCALE ***\n"

    echo "Running the timed query test"
    echo "pgbench --random-seed 666 -n -P 30 -M $PROTOCOL -j $PGBENCH_JOBS -c $PGBENCH_CLIENTS -t $PGBENCH_TRANSACTIONS $FLAGS \"$CONNSTR_TESTDB\" &> $LOGDIR/pgbench_testset_pg_${SERVER_VERSION_NUM}_q_${QUERY_MODE}_c_${PGBENCH_CLIENTS}_s_${SCALE}_p_${PARTITIONS}_prot_${PROTOCOL}_loop_${loop_count}.log"
    TEST_LOOP_START_TIME=$(date +%s)
    $PGBENCH --random-seed 666 -n -P 30 -M $PROTOCOL -j $PGBENCH_JOBS -c $PGBENCH_CLIENTS -t $PGBENCH_TRANSACTIONS $FLAGS "$CONNSTR_TESTDB" &> $LOGDIR/pgbench_testset_pg_${SERVER_VERSION_NUM}_q_${QUERY_MODE}_c_${PGBENCH_CLIENTS}_s_${SCALE}_p_${PARTITIONS}_prot_${PROTOCOL}_loop_${loop_count}.log
    TEST_LOOP_END_TIME=$(date +%s)
    LOOP_DUR_S=$((TEST_LOOP_END_TIME-TEST_LOOP_START_TIME))

    echo "Storing pg_stat_statements results into resultsdb public.pgss_results ..."

    echo "psql \"$CONNSTR_TESTDB\" -qXc \"copy (select '${EXEC_ENV}', '${TESTSET_START_TIME_PG}', '${HOSTNAME}', now(), $loop_count, $LOOP_DUR_S, ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PARTITIONS}, ${PGBENCH_TRANSACTIONS}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, query from public.pg_stat_statements where calls >= 10 and query ~* '(INSERT|UPDATE|SELECT).*pgbench') to stdout\" | psql \"$CONNSTR_RESULTSDB\" -qXc \"copy public.pgss_results from stdin\""
    psql "$CONNSTR_TESTDB" -qXc "copy (select '${EXEC_ENV}', '${TESTSET_START_TIME_PG}', '${HOSTNAME}', now(), $loop_count, $LOOP_DUR_S, ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PARTITIONS}, ${PGBENCH_TRANSACTIONS}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, query from public.pg_stat_statements where calls >= 10 and query ~* '(INSERT|UPDATE|SELECT).*pgbench') to stdout" | psql "$CONNSTR_RESULTSDB" -qXc "copy public.pgss_results from stdin"

    echo "Storing DB and table stats to ${LOGDIR}/after_run_summary_v${PGVER_MAJOR}_scale_${SCALE}_qm_${QUERY_MODE}_p_${PARTITIONS}_prot_${PROTOCOL}_loop_${loop_count}.log ..."
    psql "$CONNSTR_TESTDB" -Xe -f after_run_get_summary.sql &> "${LOGDIR}/after_run_summary_v${PGVER_MAJOR}_scale_${SCALE}_qm_${QUERY_MODE}_p_${PARTITIONS}_prot_${PROTOCOL}_loop_${loop_count}.log"

    has_pgver_been_mutated+=([$PGVER]=${IS_MUTATING[query_mode_index]})


    query_mode_index=$((query_mode_index+1))
    echo "Done with QUERY_MODE $QUERY_MODE"

done # QUERY_MODE

pgver_index=$((pgver_index+1))

echo "$BINDIR/pg_ctl --wait -t 300 -D ${DATADIR}/pg${PGVER_MAJOR} stop"
$BINDIR/pg_ctl --wait -t 300 -D ${DATADIR}/pg${PGVER_MAJOR} stop

done # BINDIR


echo "Done with PROTOCOL $PROTOCOL"
done # PGBENCH_PROTOCOLS

echo "Done with PARTITIONS $PARTITIONS"
done # PARTITIONS

echo "Done with SCALE $SCALE"
done # SCALE

LOOP_END_TIME=$(date +%s)
echo -e "\nLOOP $loop_count DONE in $((LOOP_END_TIME-LOOP_START_TIME)) s\n"

done # LOOP_COUNT

END_TIME=`date +%s`
echo -e "\n\nSCRIPT DONE in $((END_TIME-TESTSET_START_TIME)) s"
