\x on
\pset pager off
\timing on

select version();

vacuum;

select pg_database_size(current_database());

select pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0');

select pg_size_pretty(pg_total_relation_size(relid)) as total, pg_total_relation_size(relid),
	pg_size_pretty(pg_table_size(relid)) as table , pg_table_size(relid), *
	from pg_stat_user_tables order by relname;

select pg_size_pretty(pg_total_relation_size(indexrelid)) as total_idx, pg_total_relation_size(indexrelid), *
	from pg_stat_user_indexes order by relname;

select * from pg_stat_database where datname = current_database();

create extension if not exists pgstattuple;
select * from pgstattuple('pgbench_accounts');

select * from pg_stat_statements where query ~* '(SELECT|UPDATE|INSERT).*pgbench' and calls > 10 order by query;