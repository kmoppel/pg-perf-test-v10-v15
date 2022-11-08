select
    pgver,
    avg(mean_exec_time) mean_exec_time,
    avg(exec_ch) exec_ch,
    avg(stddev_exec_time) stddev_exec_time,
    avg(stddev_ch) stddev_ch,
    query
from (

select
  hostname,
  created_on,
  query_mode,
  scale,
  clients,
  protocol,
  pgver,
  mean_exec_time,
  (100.0 * (mean_exec_time - mean_exec_time_lag) / mean_exec_time_lag)::numeric(9,2) as exec_ch,
  stddev_exec_time,
  (100.0 * (stddev_exec_time - stddev_exec_time_lag) / stddev_exec_time_lag)::numeric(9,2) as stddev_ch,
  --calls,
  --(100.0 * (calls - calls_first) / calls_first)::numeric(8,1) as calls_ch,
  --rows,
  --(100.0 * (rows - rows_lag) / rows_lag)::numeric(8,1) as rows_ch,
  sb_hit_ratio,
  query::varchar(120)
from (

select
    hostname,
    created_on,
    pgver,
    query_mode,
    scale,
    clients,
    protocol,
    mean_exec_time::numeric,
    lag(mean_exec_time) over w as mean_exec_time_lag,
    calls,
    lag(calls) over w as calls_lag,
    stddev_exec_time::numeric,
    lag(stddev_exec_time) over w as stddev_exec_time_lag,
    rows,
    lag(rows) over w as rows_lag,
    (100.0* shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1) as sb_hit_ratio,
    ltrim(regexp_replace(query, E'[ \\t\\n\\r]+', ' ', 'g')) as query
  from
    public.pgss_results
  where query ~ 'pgbench'
  window w as (partition by protocol, scale, clients, query, hostname order by pgver)
  order by
    query_mode, scale, clients, protocol, query, pgver

) x
order by query_mode, scale, clients, protocol, query, hostname, pgver
) y
group by query, pgver
order by query, pgver
;