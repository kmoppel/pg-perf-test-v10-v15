select 'total ch over all queries, scales, partitions' description ;

select
  avg(exec_ch)::numeric(9,1) tot_avg_exec_ch,
  avg(stddev_ch)::numeric(9,1) tot_avg_stddev_ch
from (
select
    query, query_mode, scale, hostname,
    avg(mean_exec_time)::numeric(9,3) mean_exec_time,
    avg(exec_ch)::numeric(9,1) exec_ch,
    avg(stddev_exec_time)::numeric(9,3) stddev_exec_time,
    avg(stddev_ch)::numeric(9,1) stddev_ch,
    --(avg(calls)/1000)::numeric(9,1) calls_1k,
    avg(calls_ch)::numeric(9,1) calls_ch,
    avg(sb_hit_ratio)::numeric(9,1) sb_hit_ratio,
    avg(sb_hit_ratio_ch)::numeric(9,1) sb_hit_ratio_ch
from (

select
  query, query_mode, hostname, scale, partitions, clients, protocol, pgver,
  mean_exec_time,
  (100.0 * (mean_exec_time - mean_exec_time_lag) / mean_exec_time_lag)::numeric(9,2) as exec_ch,
  stddev_exec_time,
  (100.0 * (stddev_exec_time - stddev_exec_time_lag) / stddev_exec_time_lag)::numeric(9,2) as stddev_ch,
  calls,
  (100.0 * (calls - calls_lag) / calls)::numeric(8,1) as calls_ch,
  rows,
  (100.0 * (rows - rows_lag) / rows_lag)::numeric(8,1) as rows_ch,
  sb_hit_ratio,
  (100.0 * (sb_hit_ratio - sb_hit_ratio_lag) / sb_hit_ratio)::numeric(8,1) as sb_hit_ratio_ch
from (

select
    query, query_mode, hostname, scale, partitions, clients, protocol, pgver,
    mean_exec_time::numeric,
    lag(mean_exec_time) over w as mean_exec_time_lag,
    calls,
    lag(calls) over w as calls_lag,
    stddev_exec_time::numeric,
    lag(stddev_exec_time) over w as stddev_exec_time_lag,
    rows,
    lag(rows) over w as rows_lag,
    (100.0* shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1) as sb_hit_ratio,
    lag((100.0* shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1)) over w as sb_hit_ratio_lag
  from
    public.pgss_results
    -- where query = 'SELECT abalance FROM pgbench_accounts WHERE aid = $1'
  window w as (partition by query, query_mode, hostname, scale, partitions, clients, protocol order by pgver)
  order by
    query, query_mode, hostname, scale, partitions, clients, protocol, pgver

) x
order by query, query_mode, hostname, scale, partitions, clients, protocol, pgver
) y
where exec_ch notnull
group by query, query_mode, scale, hostname
order by query, query_mode, scale, hostname
) z
;





select 'total ch per scale / query' description ;

select
  query,
  scale,
  avg(exec_ch)::numeric(9,1) tot_avg_exec_ch,
  avg(stddev_ch)::numeric(9,1) tot_avg_stddev_ch
from (
select
    query, query_mode, scale, hostname,
    avg(mean_exec_time)::numeric(9,3) mean_exec_time,
    avg(exec_ch)::numeric(9,1) exec_ch,
    avg(stddev_exec_time)::numeric(9,3) stddev_exec_time,
    avg(stddev_ch)::numeric(9,1) stddev_ch,
    --(avg(calls)/1000)::numeric(9,1) calls_1k,
    avg(calls_ch)::numeric(9,1) calls_ch,
    avg(sb_hit_ratio)::numeric(9,1) sb_hit_ratio,
    avg(sb_hit_ratio_ch)::numeric(9,1) sb_hit_ratio_ch
from (

select
  query, query_mode, hostname, scale, partitions, clients, protocol, pgver,
  mean_exec_time,
  (100.0 * (mean_exec_time - mean_exec_time_lag) / mean_exec_time_lag)::numeric(9,2) as exec_ch,
  stddev_exec_time,
  (100.0 * (stddev_exec_time - stddev_exec_time_lag) / stddev_exec_time_lag)::numeric(9,2) as stddev_ch,
  calls,
  (100.0 * (calls - calls_lag) / calls)::numeric(8,1) as calls_ch,
  rows,
  (100.0 * (rows - rows_lag) / rows_lag)::numeric(8,1) as rows_ch,
  sb_hit_ratio,
  (100.0 * (sb_hit_ratio - sb_hit_ratio_lag) / sb_hit_ratio)::numeric(8,1) as sb_hit_ratio_ch
from (

select
    query, query_mode, hostname, scale, partitions, clients, protocol, pgver,
    mean_exec_time::numeric,
    lag(mean_exec_time) over w as mean_exec_time_lag,
    calls,
    lag(calls) over w as calls_lag,
    stddev_exec_time::numeric,
    lag(stddev_exec_time) over w as stddev_exec_time_lag,
    rows,
    lag(rows) over w as rows_lag,
    (100.0* shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1) as sb_hit_ratio,
    lag((100.0* shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1)) over w as sb_hit_ratio_lag
  from
    public.pgss_results
    -- where query = 'SELECT abalance FROM pgbench_accounts WHERE aid = $1'
  window w as (partition by query, query_mode, hostname, scale, partitions, clients, protocol order by pgver)
  order by
    query, query_mode, hostname, scale, partitions, clients, protocol, pgver

) x
order by query, query_mode, hostname, scale, partitions, clients, protocol, pgver
) y
where exec_ch notnull
group by query, query_mode, scale, hostname
order by query, query_mode, scale, hostname
) z
group by grouping sets ((query, scale), (scale), ())
order by query, scale
;









select 'partition count effects' description ;
select
  partitions,
  scale,
  avg(exec_ch)::numeric(9,1) tot_avg_exec_ch,
  avg(stddev_ch)::numeric(9,1) tot_avg_stddev_ch
from (

select
    query, query_mode, scale, hostname, partitions,
    avg(mean_exec_time)::numeric(9,3) mean_exec_time,
    avg(exec_ch)::numeric(9,1) exec_ch,
    avg(stddev_exec_time)::numeric(9,3) stddev_exec_time,
    avg(stddev_ch)::numeric(9,1) stddev_ch,
    -- (avg(calls)/1000)::numeric(9,1) calls_1k,
    -- avg(calls_ch)::numeric(9,1) calls_ch,
    avg(sb_hit_ratio)::numeric(9,1) sb_hit_ratio,
    avg(sb_hit_ratio_ch)::numeric(9,1) sb_hit_ratio_ch
from (

select
  query, query_mode, hostname, scale, clients, protocol, partitions, pgver,
  mean_exec_time,
  (100.0 * (mean_exec_time - mean_exec_time_lag) / mean_exec_time_lag)::numeric(9,2) as exec_ch,
  stddev_exec_time,
  (100.0 * (stddev_exec_time - stddev_exec_time_lag) / stddev_exec_time_lag)::numeric(9,2) as stddev_ch,
  /*
  calls,
  (100.0 * (calls - calls_lag) / calls)::numeric(8,1) as calls_ch,
  rows,
  (100.0 * (rows - rows_lag) / rows_lag)::numeric(8,1) as rows_ch,
  */
  sb_hit_ratio,
  (100.0 * (sb_hit_ratio - sb_hit_ratio_lag) / sb_hit_ratio)::numeric(8,1) as sb_hit_ratio_ch
from (

select
    query, query_mode, hostname, scale, partitions, clients, protocol, pgver,
    mean_exec_time::numeric,
    lag(mean_exec_time) over w as mean_exec_time_lag,
    -- calls,
    -- lag(calls) over w as calls_lag,
    stddev_exec_time::numeric,
    lag(stddev_exec_time) over w as stddev_exec_time_lag,
    -- rows,
    -- lag(rows) over w as rows_lag,
    (100.0* shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1) as sb_hit_ratio,
    lag((100.0* shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1)) over w as sb_hit_ratio_lag
  from
    public.pgss_results
  window w as (partition by query, query_mode, hostname, scale, partitions, clients, protocol order by partitions, pgver)
  order by
    query, query_mode, hostname, scale, clients, protocol, partitions, pgver

) x
order by query, query_mode, hostname, scale, clients, protocol, partitions, pgver

) y
where exec_ch notnull
group by query, query_mode, scale, hostname, partitions
order by query, query_mode, scale, hostname, partitions

) z
group by grouping sets ((partitions, scale), ())
order by partitions, scale
;


select 'partition count effects' description ;
select
  query,
  scale,
  partitions,
  avg(exec_ch)::numeric(9,1) tot_avg_exec_ch,
  avg(stddev_ch)::numeric(9,1) tot_avg_stddev_ch
from (

select
    query, query_mode, scale, hostname, partitions,
    avg(mean_exec_time)::numeric(9,3) mean_exec_time,
    avg(exec_ch)::numeric(9,1) exec_ch,
    avg(stddev_exec_time)::numeric(9,3) stddev_exec_time,
    avg(stddev_ch)::numeric(9,1) stddev_ch,
    -- (avg(calls)/1000)::numeric(9,1) calls_1k,
    -- avg(calls_ch)::numeric(9,1) calls_ch,
    avg(sb_hit_ratio)::numeric(9,1) sb_hit_ratio,
    avg(sb_hit_ratio_ch)::numeric(9,1) sb_hit_ratio_ch
from (

select
  query, query_mode, hostname, scale, clients, protocol, pgver, partitions,
  mean_exec_time,
  (100.0 * (mean_exec_time - mean_exec_time_first) / mean_exec_time_first)::numeric(9,2) as exec_ch,
  stddev_exec_time,
  (100.0 * (stddev_exec_time - stddev_exec_time_first) / stddev_exec_time_first)::numeric(9,2) as stddev_ch,
  sb_hit_ratio,
  (100.0 * (sb_hit_ratio - sb_hit_ratio_first) / sb_hit_ratio)::numeric(8,1) as sb_hit_ratio_ch
from (

select
    query, query_mode, hostname, scale, partitions, clients, protocol, pgver,
    mean_exec_time::numeric,
    first_value(mean_exec_time) over w as mean_exec_time_first,
    -- calls,
    -- lag(calls) over w as calls_lag,
    stddev_exec_time::numeric,
    first_value(stddev_exec_time) over w as stddev_exec_time_first,
    -- rows,
    -- lag(rows) over w as rows_lag,
    (100.0* shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1) as sb_hit_ratio,
    first_value((100.0* shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1)) over w as sb_hit_ratio_first
  from
    public.pgss_results
    -- where scale > 800
  window w as (partition by query, query_mode, hostname, scale, pgver, clients, protocol order by partitions)
  order by
    query, query_mode, hostname, scale, pgver, clients, protocol, partitions

) x
order by query, query_mode, hostname, scale, clients, protocol, pgver, partitions

) y
where exec_ch notnull
group by query, query_mode, scale, hostname, partitions
order by query, query_mode, scale, hostname, partitions

) z
group by grouping sets ((query, partitions, scale), (scale), ())
order by query, scale, partitions
;
