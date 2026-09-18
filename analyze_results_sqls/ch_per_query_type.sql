select 'total ch per query / scale' as description ;

select
  query_mode,
  query_type,
  scale,
  avg(exec_ch)::numeric(9,1) tot_avg_exec_ch,
  avg(stddev_ch)::numeric(9,1) tot_avg_stddev_ch,
  avg(sb_hit_ratio)::numeric(9,1) tot_avg_sb_hit_ratio,
  avg(sb_hit_ratio_ch)::numeric(9,1) tot_avg_sb_hit_ratio_ch
from (

    select
        split_part(query, ' ', 1) as query_type, query_mode, scale,
        avg(mean_exec_time)::numeric(9,3) mean_exec_time,
        avg(exec_ch)::numeric(9,1) exec_ch,
        avg(stddev_exec_time)::numeric(9,3) stddev_exec_time,
        avg(stddev_ch)::numeric(9,1) stddev_ch,
        avg(sb_hit_ratio)::numeric(9,1) sb_hit_ratio,
        avg(sb_hit_ratio_ch)::numeric(9,1) sb_hit_ratio_ch
    from (

        select
          test_start_time, query, query_mode, hostname, scale, partitions, clients, protocol, pgver,
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
                avg((100.0::numeric * shared_blks_hit / (shared_blks_hit + shared_blks_read))::numeric(8,1)) as sb_hit_ratio
              from
                -- pgss_results_m8id_xlarge_tpcc
                pgss_results_agg_bench_sync
                --pgss_results_aws_c8_800_syncc_upd_only
                --pgss_results_agg
              -- where
              --  test_start_time <> '2026-07-29 13:15:32.52292+03'
              group by
                test_start_time, query, query_mode, hostname, scale, partitions, clients, protocol, pgver
              order by
                test_start_time, query, query_mode, hostname, scale, partitions, clients, protocol, pgver
          ) loop_agg
          window w as (partition by test_start_time, query, query_mode, hostname, scale, partitions, clients, protocol order by pgver)
          order by test_start_time, query, query_mode, hostname, scale, partitions, clients, protocol, pgver

        ) x

    ) y
    where exec_ch notnull
    group by query, query_mode, scale
    order by query, query_mode, scale

) z
group by grouping sets ((query_mode, query_type, scale), ())
order by query_mode, query_type, scale
;
