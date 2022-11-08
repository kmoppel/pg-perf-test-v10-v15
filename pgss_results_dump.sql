--
-- PostgreSQL database dump
--

-- Dumped from database version 15.0 (Ubuntu 15.0-1.pgdg22.04+1)
-- Dumped by pg_dump version 15.0 (Ubuntu 15.0-1.pgdg22.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: pgss_results; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pgss_results (
    exec_env text,
    test_start_time timestamp with time zone,
    hostname text,
    created_on timestamp with time zone,
    pgver numeric,
    pgminor integer,
    scale integer,
    duration integer,
    clients integer,
    protocol text,
    query_mode text,
    mean_exec_time double precision,
    stddev_exec_time double precision,
    calls bigint,
    rows bigint,
    shared_blks_hit bigint,
    shared_blks_read bigint,
    blk_read_time double precision,
    blk_write_time double precision,
    query text
);


ALTER TABLE public.pgss_results OWNER TO postgres;

--
-- Data for Name: pgss_results; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pgss_results (exec_env, test_start_time, hostname, created_on, pgver, pgminor, scale, duration, clients, protocol, query_mode, mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query) FROM stdin;
local	2022-10-20 14:33:15.395808+03	fuji	2022-10-26 06:24:14.380243+03	15	150000	5000	259200	8	prepared	skip-some-updates	0.04693180403161521	0.052605250507469614	1000000000	1000000000	20021634297	4867	2310.498606999999	47730.21049799505	INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
local	2022-10-20 14:33:15.395808+03	fuji	2022-10-26 06:24:14.380243+03	15	150000	5000	259200	8	prepared	skip-some-updates	0.008343880030236641	0.01855993157546006	1000000000	1000000000	5008671297	0	0	0	SELECT abalance FROM pgbench_accounts WHERE aid = $1
local	2022-10-20 14:33:15.395808+03	fuji	2022-10-26 06:24:14.380243+03	15	150000	5000	259200	8	prepared	skip-some-updates	3.5307225310174855	5.6566635790203375	1000000000	1000000000	14597390085	2688580119	3017351252.04431	19827377.537961364	UPDATE pgbench_accounts SET abalance = abalance + $1 WHERE aid = $2
local	2022-10-20 14:33:15.395808+03	fuji	2022-11-01 04:04:27.890498+02	10	100022	5000	259200	8	prepared	skip-some-updates	0.00795333092909916	0.0138601716406893	1000000000	1000000000	5024448036	0	0	0	SELECT abalance FROM pgbench_accounts WHERE aid = $1
local	2022-10-20 14:33:15.395808+03	fuji	2022-11-01 04:04:27.890498+02	10	100022	5000	259200	8	prepared	skip-some-updates	3.65297072692547	2.85029862485875	1000000000	1000000000	13663220522	2781190338	3274252610.48951	25404628.349046	UPDATE pgbench_accounts SET abalance = abalance + $1 WHERE aid = $2
local	2022-10-20 14:33:15.395808+03	fuji	2022-11-01 04:04:27.890498+02	10	100022	5000	259200	8	prepared	skip-some-updates	0.0476903469922874	0.0551724704962927	1000000000	1000000000	20018410008	6374496	3543.35342600001	58294.7351899983	INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
local	2022-10-20 14:19:10.974471+03	testkast	2022-10-24 17:18:58.663597+03	15	150000	5000	259200	8	prepared	skip-some-updates	0.061359125450643946	0.0781308090509615	1000000000	1000000000	20022041638	4766	926.5386099999994	54204.61161100422	INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
local	2022-10-20 14:19:10.974471+03	testkast	2022-10-24 17:18:58.663597+03	15	150000	5000	259200	8	prepared	skip-some-updates	0.010294309797969872	0.028470088700045006	1000000000	1000000000	5008737745	0	0	0	SELECT abalance FROM pgbench_accounts WHERE aid = $1
local	2022-10-20 14:19:10.974471+03	testkast	2022-10-24 17:18:58.663597+03	15	150000	5000	259200	8	prepared	skip-some-updates	2.2944629249246806	5.14052656313694	1000000000	1000000000	14580730680	2681226182	1750552540.3338182	24056830.513475806	UPDATE pgbench_accounts SET abalance = abalance + $1 WHERE aid = $2
local	2022-10-20 14:19:10.974471+03	testkast	2022-10-28 20:26:33.513278+03	10	100022	5000	259200	8	prepared	skip-some-updates	2.19749110103023	4.26577379993823	1000000000	1000000000	13784695898	2786554290	1690338996.60455	27548150.9639318	UPDATE pgbench_accounts SET abalance = abalance + $1 WHERE aid = $2
local	2022-10-20 14:19:10.974471+03	testkast	2022-10-28 20:26:33.513278+03	10	100022	5000	259200	8	prepared	skip-some-updates	0.010177108431064	0.0265299476350876	1000000000	1000000000	5024892022	1	0.002492	0.009062	SELECT abalance FROM pgbench_accounts WHERE aid = $1
local	2022-10-20 14:19:10.974471+03	testkast	2022-10-28 20:26:33.513278+03	10	100022	5000	259200	8	prepared	skip-some-updates	0.0616764610682732	0.0757845321960745	1000000000	1000000000	20018768558	6374299	1231.22623	60237.1328209997	INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
\.


--
-- PostgreSQL database dump complete
--

