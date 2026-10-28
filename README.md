# pg-perf-test

Runs 5 pgbench based tests for various Postgres version / pgbench scale / partition count configs:

* Key reads
* Batched (10k) Key reads
* Key updates

# Analyzing the results

For a quick summary run `total_weighted_avg_test_duration_ch.sql` on the `resultsdb`.

# v18 vs v19 beta4 / rc1 summary

For *pgbench* my testing on a dozen different cloud VMs (EC2 metal + Hetzner dedicated) give v19 a few percentage points
of test runtime improvement. For [pgbench-tpcc-like](https://github.com/kmoppel/pgbench-tpcc-like) a few percentage points more.