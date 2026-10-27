-- Weighted average change: each comparison to the previous pgver is weighted by its share (%) of the total sum of (loop_dur + lag_loop_dur)
select query_mode,
  (sum(dur_ch * weight_pct) / sum(weight_pct))::numeric(5,1) as weighted_avg_dur_ch
from (
select *, 100::numeric * (loop_dur - lag_loop_dur) / lag_loop_dur as dur_ch,
  100 * (loop_dur + lag_loop_dur) / sum(loop_dur + lag_loop_dur) over () as weight_pct
from (
    select *, lag(loop_dur) over w as lag_loop_dur
    from (
    select distinct
      hostname, test_start_time, query_mode, scale, loop_count, pgver, loop_dur
    from pgss_results order by 1, 2, 3, 4, 5, 6
    ) x
    window w as (partition by hostname, test_start_time, query_mode, scale, loop_count order by pgver)
) y
where lag_loop_dur notnull
) z
group by rollup (query_mode)
order by 1 nulls last
;


/*

CREATE TABLE public.pgss_results (
    exec_env text,
    test_start_time timestamp with time zone,
    hostname text,
    created_on timestamp with time zone,
    loop_count integer,
    loop_dur integer,
    pgver numeric,
    pgminor integer,
    scale integer,
    partitions integer,
    transactions integer,
    clients integer,
    protocol text,
    query_mode text,
    mean_exec_time double precision,
    stddev_exec_time double precision,
    calls bigint,
    rows bigint,
    shared_blks_hit bigint,
    shared_blks_read bigint,
    query text
);

*/
