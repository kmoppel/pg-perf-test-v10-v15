#!/bin/bash

set -e

PGHOST_TESTDB=127.0.0.1
PGPORT_TESTDB=6666
PGDATABASE_TESTDB=postgres
PGUSER_TESTDB=postgres
PGPASSWORD_TESTDB=postgres
CONNSTR_TESTDB="postgresql://${PGUSER_TESTDB}:${PGPASSWORD_TESTDB}@${PGHOST_TESTDB}:${PGPORT_TESTDB}/${PGDATABASE_TESTDB}"  # instances will be initialized
CONNSTR_RESULTSDB="postgresql://postgres:somepass@somehost:5432/resultsdb" # assumed existing and >= v13 for storing pg_stat_statement results from test instances
EXEC_ENV=gcp

# paths to Postgres installations to include into testing
declare -a BINDIRS
declare -a PGVER_MAJORS

BINDIRS+=("/usr/lib/postgresql/10/bin")
PGVER_MAJORS+=("10")
BINDIRS+=("/usr/lib/postgresql/11/bin")
PGVER_MAJORS+=("11")
BINDIRS+=("/usr/lib/postgresql/12/bin")
PGVER_MAJORS+=("12")
BINDIRS+=("/usr/lib/postgresql/13/bin")
PGVER_MAJORS+=("13")
BINDIRS+=("/usr/lib/postgresql/14/bin")
PGVER_MAJORS+=("14")
BINDIRS+=("/usr/lib/postgresql/15/bin")
PGVER_MAJORS+=("15")


PGBENCH=/usr/lib/postgresql/14/bin/pgbench


REMOVE_INSTANCES=1  # if 1 then 'rm -rf' each test instance besides the last after testing. set to 1 if low on disk
DATADIR=/tmp/pgbench_testset
mkdir -p $DATADIR

PGBENCH_SCALES="200 750 1250" # ~3 GB (Shared buffers) / 11 GB (RAM) / 18 GB (some light disk access, assuming 16GB RAM) DB size
                              # Note though that we increase that by ~ 30% with a reduced pgbench_accounts clone to be able to test JOIN
#PGBENCH_SCALES="1"
PGBENCH_INIT_FLAGS="--foreign-keys -q"
PGBENCH_CLIENTS=2
PGBENCH_DURATION=3600
PGBENCH_CACHE_WARMUP_DURATION=300
PROTOCOLS="simple prepared" # pgbench --protocol flag

declare -a QUERY_MODES
declare -a QUERY_FLAGS

#QUERY_MODES+=("select-only") # covered by --skip-some-updates actually
#QUERY_FLAGS+=("--select-only")
QUERY_MODES+=("avg-acc-balance")
QUERY_FLAGS+=("-f sql-avg-acc-balance.sql")
QUERY_MODES+=("top-5-balances-per-branch") # assumes: create index pgbench_accounts_bid_idx on pgbench_accounts(bid);
QUERY_FLAGS+=("-f sql-top-5-balances-per-branch.sql")
QUERY_MODES+=("join-on-reduced-accounts") # assumes: pgbench_accounts_reduced table + index
QUERY_FLAGS+=("-f sql-join-on-reduced-accounts.sql")
QUERY_MODES+=("skip-some-updates")
QUERY_FLAGS+=("--skip-some-updates") # should be last as changes initialized data and makes things more undeterministic


SQL_PGSS_SETUP="CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA public;"
SQL_PGSS_RESULTS_SETUP="CREATE TABLE IF NOT EXISTS public.pgss_results AS SELECT ''::text AS exec_env, now() AS test_start_time, ''::text AS hostname, now() AS created_on, 0::numeric AS pgver, 0 as pgminor, 0 AS scale, 0 AS duration, 0 AS clients, ''::text AS protocol, ''::text AS query_mode, mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query FROM public.pg_stat_statements WHERE false;"
SQL_PGSS_RESET="SELECT public.pg_stat_statements_reset();"


function exec_sql() {
    psql "$CONNSTR_TESTDB" -Xqc "$1"
}

function exec_sql_resultsdb() {
    psql "$CONNSTR_RESULTSDB" -Xqc "$1"
}

if [ "$REMOVE_INSTANCES" -gt 0 ]; then
  rm -rf $DATADIR
fi

HOSTNAME=`hostname`
START_TIME=`date +%s`
START_TIME_PG=`psql "$CONNSTR_RESULTSDB" -qAXtc "select now();"`

echo "Ensuring pg_stat_statements extension on result server and public.pgss_results table ..."
exec_sql_resultsdb "$SQL_PGSS_SETUP"
exec_sql_resultsdb "$SQL_PGSS_RESULTS_SETUP"


### Loop over all postgres versions, creating instances one by one, applying some PG config settings and starting

i=0
for BINDIR in "${BINDIRS[@]}" ; do
PGVER_MAJOR=${PGVER_MAJORS[i]}

echo -e "\n\n\n################ Initializing PGVER $PGVER_MAJOR ################\n"

echo "$BINDIR/initdb --auth=trust --data-checksums --username=$PGUSER_TESTDB $DATADIR/pg${PGVER_MAJOR}  >/dev/null"
$BINDIR/initdb --auth=trust --data-checksums --username=$PGUSER_TESTDB ${DATADIR}/pg${PGVER_MAJOR}  >/dev/null

cat postgresql.tune.conf >> ${DATADIR}/pg${PGVER_MAJOR}/postgresql.conf
echo "port=${PGPORT_TESTDB}" >> ${DATADIR}/pg${PGVER_MAJOR}/postgresql.conf

echo "$BINDIR/pg_ctl --wait --log ${DATADIR}/pg${PGVER_MAJOR}/postgresql.log -D ${DATADIR}/pg${PGVER_MAJOR} start"
$BINDIR/pg_ctl --wait --log ${DATADIR}/pg${PGVER_MAJOR}/postgresql.log -D ${DATADIR}/pg${PGVER_MAJOR} start

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

echo "Creating test data using pgbench ..."
echo "pgbench -i -q $PGBENCH_INIT_FLAGS -s $SCALE \"$CONNSTR_TESTDB\" >/dev/null"
$PGBENCH -i -q $PGBENCH_INIT_FLAGS -s $SCALE "$CONNSTR_TESTDB" >/dev/null

echo "Creating an extra index on pgbench_accounts..."
echo "create index pgbench_accounts_bid_idx on pgbench_accounts(bid); ..."
exec_sql "create index pgbench_accounts_bid_idx on pgbench_accounts(bid);"

echo "Creating a reduced copy of pgbench_accounts..."
echo "drop table if exists pgbench_accounts_reduced;"
exec_sql "drop table if exists pgbench_accounts_reduced;"
echo "create table pgbench_accounts_reduced as select * from pgbench_accounts where aid % 4 = 0 order by aid;"
exec_sql "create table pgbench_accounts_reduced as select * from pgbench_accounts where aid % 4 = 0 order by aid;"

echo "vacuum analyze pgbench_accounts_reduced;"
exec_sql "vacuum analyze pgbench_accounts_reduced;"

echo "create unique index on pgbench_accounts_reduced (aid);"
exec_sql "create unique index on pgbench_accounts_reduced (aid);"

echo "Disabling AUTOVACUUM for pgbench_accounts_reduced to reduce background randomness..." # NB! Not suitable for very long-running tests
exec_sql "alter table pgbench_accounts_reduced set (autovacuum_enabled = false);"

echo "Disabling AUTOVACUUM for pgbench_accounts to reduce background randomness..." # NB! Not suitable for very long-running tests
exec_sql "alter table pgbench_accounts set (autovacuum_enabled = false);"

j=0
for QUERY_MODE in "${QUERY_MODES[@]}" ; do
  FLAGS=${QUERY_FLAGS[j]}

  echo -e "\n*** Testing query model: $QUERY_MODE with protocol $PROTOCOL ***\n"

  echo "Doing cache warmup for $PGBENCH_CACHE_WARMUP_DURATION seconds..."
  echo "pgbench -S -c $PGBENCH_CLIENTS -T $PGBENCH_CACHE_WARMUP_DURATION \"$CONNSTR_TESTDB\" >/dev/null"
  $PGBENCH -S -c $PGBENCH_CLIENTS -T $PGBENCH_CACHE_WARMUP_DURATION "$CONNSTR_TESTDB" >/dev/null

  for PROTOCOL in $PROTOCOLS ; do
  
  echo "Reseting pg_stat_statements..."
  exec_sql "$SQL_PGSS_RESET" >/dev/null

  echo "Running the timed query test"
  echo "pgbench --random-seed 666 -M $PROTOCOL -c $PGBENCH_CLIENTS -T $PGBENCH_DURATION $FLAGS \"$CONNSTR_TESTDB\" >/dev/null"
  $PGBENCH --random-seed 666 -M $PROTOCOL -c $PGBENCH_CLIENTS -T $PGBENCH_DURATION $FLAGS "$CONNSTR_TESTDB" >/dev/null

  echo "Storing pg_stat_statements results into resultsdb public.pgss_results ..."

  if [ "$SERVER_VERSION_NUM" -ge "130000" ]; then
    echo "psql \"$CONNSTR_TESTDB\" -qXc \"copy (select '${EXEC_ENV}', '${START_TIME_PG}', '${HOSTNAME}', now(), ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PGBENCH_DURATION}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query from public.pg_stat_statements where calls > 1 and query ~* '(INSERT|UPDATE|SELECT).*pgbench_accounts') to stdout\" | psql \"$CONNSTR_RESULTSDB\" -qXc \"copy public.pgss_results from stdin\""
    psql "$CONNSTR_TESTDB" -qXc "copy (select '${EXEC_ENV}', '${START_TIME_PG}', '${HOSTNAME}', now(), ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PGBENCH_DURATION}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query from public.pg_stat_statements where calls > 1 and query ~* '(INSERT|UPDATE|SELECT).*pgbench_accounts') to stdout" | psql "$CONNSTR_RESULTSDB" -qXc "copy public.pgss_results from stdin"
  else
    echo "psql \"$CONNSTR_TESTDB\" -qXc \"copy (select '${EXEC_ENV}', '${START_TIME_PG}', '${HOSTNAME}', now(), ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PGBENCH_DURATION}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_time, stddev_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query from public.pg_stat_statements where calls > 1 and query ~* '(INSERT|UPDATE|SELECT).*pgbench_accounts') to stdout\" | psql \"$CONNSTR_RESULTSDB\" -qXc \"copy public.pgss_results from stdin\""
    psql "$CONNSTR_TESTDB" -qXc "copy (select '${EXEC_ENV}', '${START_TIME_PG}', '${HOSTNAME}', now(), ${PGVER_MAJOR}, ${SERVER_VERSION_NUM}, ${SCALE}, ${PGBENCH_DURATION}, ${PGBENCH_CLIENTS}, '${PROTOCOL}', '${QUERY_MODE}', mean_time, stddev_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query from public.pg_stat_statements where calls > 1 and query ~* '(INSERT|UPDATE|SELECT).*pgbench_accounts') to stdout" | psql "$CONNSTR_RESULTSDB" -qXc "copy public.pgss_results from stdin"
  fi
  
  done # protocol

  j=$((j+1))

echo "Done with QUERY_MODE $QUERY_MODE with protocol $PROTOCOL"
done # QUERY_MODE

echo "Done with SCALE $SCALE"
done # SCALE

echo "$BINDIR/pg_ctl --wait -t 300 -D ${DATADIR}/pg${PGVER_MAJOR} stop"
$BINDIR/pg_ctl --wait -t 300 -D ${DATADIR}/pg${PGVER_MAJOR} stop

i=$((i+1))

if [ "$REMOVE_INSTANCES" -gt 0 ]; then
  if [ $i -lt ${#BINDIRS[@]} ]; then
    echo "Removing instance $PGVER_MAJOR ..."
    rm -rf ${DATADIR}/pg${PGVER_MAJOR}
  fi
fi


done # BINDIR

END_TIME=`date +%s`
echo -e "\nDONE in $((END_TIME-START_TIME)) s"
