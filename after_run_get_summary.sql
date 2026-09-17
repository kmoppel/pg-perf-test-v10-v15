\x off
\pset pager off
\timing off

select now();

select version();

select pg_size_pretty(pg_database_size(current_database())) as db_size;
select pg_database_size(current_database()) as db_size_bytes;

select pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0');

\x on
select (100.0 * ( blks_hit::numeric / ( blks_hit + blks_read)))::numeric(6,2) as sb_hit_rate from pg_stat_database where datname = current_database();
select 'pg_stat_database' as view, * from pg_stat_database where datname = current_database();

\x off
select 'pg_stat_io' as view, * from pg_stat_io where backend_type in ('client backend', 'background worker') and (reads > 0 or writes > 0);

select 'pg_statio_all_tables' as view, * from pg_statio_all_tables where relname ~ '^pgbench\_' order by relname;
select 'pg_stat_bgwriter' as view, pg_size_pretty ( buffers_clean * 8192 ) buffers_clean_pretty, * from  pg_stat_bgwriter ;
select 'pg_stat_checkpointer' as view, * from  pg_stat_checkpointer ;

select 'pg_stat_user_tables' as view,
  pg_size_pretty(sum(pg_table_size(relid))) as pg_table_size_pretty, sum(pg_table_size(relid)) as pg_table_size,
  sum(seq_scan) seq_scan, sum(idx_scan) idx_scan, sum(idx_tup_fetch) idx_tup_fetch, sum(n_tup_ins) n_tup_ins, sum(n_tup_upd) n_tup_upd, sum(n_tup_del) n_tup_del,
  sum(n_tup_hot_upd) n_tup_hot_upd, sum(n_tup_newpage_upd) n_tup_newpage_upd
from pg_stat_user_tables where relname ~ '^pgbench\_accounts';


create extension if not exists pgstattuple;
select count(relname) partitions, avg(tuple_percent)::numeric(5,2) tuple_percent, avg(dead_tuple_percent)::numeric(5,2) dead_tuple_percent, avg(free_percent)::numeric(5,2) free_percent from pg_class, pgstattuple( oid ) where relname ~ '^pgbench_accounts' and relkind = 'r' ;
