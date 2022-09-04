-- assumes: create index pgbench_accounts_bid_idx on pgbench_accounts(bid);
select bid, abalance from pgbench_branches b join lateral (select abalance from pgbench_accounts where bid = b.bid order by abalance desc limit 5) a on true;
