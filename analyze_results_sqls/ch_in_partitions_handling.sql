select 'partition count effects for pgbench betweeng PG versions' as description ;

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
    avg(sb_hit_ratio)::numeric(9,1) sb_hit_ratio,
    avg(sb_hit_ratio_ch)::numeric(9,1) sb_hit_ratio_ch
from (

select
  query, query_mode, hostname, scale, clients, protocol, partitions, pgver,
  mean_exec_time,
  (100.0 * (mean_exec_time - mean_exec_time_lag) / mean_exec_time_lag)::numeric(9,2) as exec_ch,
  stddev_exec_time,
  (100.0 * (stddev_exec_time - stddev_exec_time_lag) / stddev_exec_time_lag)::numeric(9,2) as stddev_ch,
  sb_hit_ratio,
  (100.0 * (sb_hit_ratio - sb_hit_ratio_lag) / sb_hit_ratio)::numeric(8,1) as sb_hit_ratio_ch
from (

      select
        test_start_time, query, query_mode, hostname, scale, partitions, clients, protocol, pgver,
        mean_exec_time,
        lag(mean_exec_time) over w as mean_exec_time_lag,
        stddev_exec_time,
        lag(stddev_exec_time) over w as stddev_exec_time_lag,
        sb_hit_ratio,
        lag(sb_hit_ratio) over w as sb_hit_ratio_lag
      from (
          select
            test_start_time, query, query_mode, hostname, scale, partitions, clients, protocol, pgver, count(*) as loops,
            avg(mean_exec_time::numeric) as mean_exec_time,
            avg(stddev_exec_time::numeric) as stddev_exec_time,
            avg((100::numeric * shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1)) as sb_hit_ratio
          from
            pgss_results_agg
          group by
            test_start_time, query, query_mode, hostname, scale, partitions, clients, protocol, pgver
          order by
            test_start_time, query, query_mode, hostname, scale, partitions, clients, protocol, pgver
      ) loop_agg
      where query_mode <> 'tpcc-like'
      window w as (partition by test_start_time, query, query_mode, hostname, scale, partitions, clients, protocol order by partitions, pgver)
      order by
        test_start_time, query, query_mode, hostname, scale, clients, protocol, partitions, pgver

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
