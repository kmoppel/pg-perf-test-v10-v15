select query_mode, avg(dur_ch)::numeric(5,1) as avg_dur_ch from (
select *, (100::numeric * (loop_dur - lag_loop_dur) / lag_loop_dur)::numeric(5,1) as dur_ch from (
    select *, lag(loop_dur) over w as lag_loop_dur
    from (
    select distinct
      hostname, test_start_time, query_mode, scale, loop_count, pgver, loop_dur
    from pgss_results order by 1, 2, 3, 4, 5, 6
    ) x
    window w as (partition by hostname, test_start_time, query_mode, scale, loop_count order by pgver)
) y
where lag_loop_dur notnull
order by hostname, test_start_time, query_mode, scale, loop_count, pgver, loop_dur
) z
group by rollup (query_mode)
order by 1 nulls last
;