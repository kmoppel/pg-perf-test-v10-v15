-- Ca 2MB batch
\set aid_from random(1, 100000 * :scale)
\set aid_to :aid_from + 10000
SELECT abalance FROM pgbench_accounts WHERE aid BETWEEN :aid_from and :aid_to
