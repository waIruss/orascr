-- =====================================================================
-- Real-Time SQL Plan Management - test script
-- Target  : Oracle 23ai / 26ai Enterprise Edition, one PDB
-- Needs   : ADMINISTER SQL MANAGEMENT OBJECT (DBMS_SPM.CONFIGURE),
--           SELECT on DBA_* views. One step (ACCEPT_PLANS) is documented
--           by Oracle as run by SYS in the PDB - see step 0.
-- Client  : SQL*Plus / SQLcl recommended. All test queries run through
--           EXECUTE IMMEDIATE so the SQL text (and its /* RTSPM_TCx */
--           tag) is identical on every run. Static PL/SQL SQL would strip
--           the comment.
--
-- Test cases
--   TC1  Plan regression detected and repaired in the foreground
--   TC2  A better new plan is NOT blocked                 (safety)
--   TC3  No ASTS history yet -> no protection             (limitation)
--   TC4  Accepted plan becomes non-reproducible            (safety)
--
-- TIMELINE - the test has two phases:
--   Phase 1  create data, run good plans, WAIT for ASTS capture
--            (Auto STS Capture Task, default interval 15 min)
--   Phase 2  break plans and observe
-- =====================================================================
 
set serveroutput on timing on linesize 220 pagesize 200
column sql_text format a70
 
-- =====================================================================
-- 0. Preconditions and enablement
-- =====================================================================
select banner_full from v$version;
 
-- Real-time SPM status (AUTO = real-time SPM on)
select parameter_name, parameter_value
from   dba_sql_management_config
where  parameter_name = 'AUTO_SPM_EVOLVE_TASK';
 
-- Must be FALSE: real-time SPM is separate from baseline auto-capture
show parameter optimizer_capture_sql_plan_baselines
 
-- Background tasks: ASTS capture + SPM evolve
select task_name, enabled, interval, status
from   dba_autotask_schedule_control
where  dbid = sys_context('userenv','con_dbid')
and    task_name in ('Auto STS Capture Task','Auto SPM Task');
 
-- Enable (records previous value above for rollback)
exec dbms_spm.configure('AUTO_SPM_EVOLVE_TASK','AUTO')
 
-- Per Oracle optimizer blog, on non-autonomous systems run as SYS in the PDB:
-- exec dbms_spm.set_evolve_task_parameter('SYS_AUTO_SPM_EVOLVE_TASK','ACCEPT_PLANS','TRUE')
 
-- Re-check: AUTO_SPM_EVOLVE_TASK = AUTO, Auto STS Capture Task ENABLED
 
-- =====================================================================
-- 1. Setup  (~1M rows, ~220 MB)
-- =====================================================================
drop table rtspm_t purge;
create table rtspm_t (
  id    number       not null,
  grp   number       not null,   -- TC1 / TC4 : 10 rows per value, indexed
  grp2  number       not null,   -- TC3       : same data, own index
  uk    number       not null,   -- TC2       : unique, NOT indexed yet
  val   number       not null,
  pad   varchar2(200)
);
insert /*+ append */ into rtspm_t
select level, mod(level,100000), mod(level,100000), level,
       mod(level,997), rpad('x',200,'x')
from dual connect by level <= 1000000;
commit;
 
create index rtspm_grp_ix  on rtspm_t(grp);
create index rtspm_grp2_ix on rtspm_t(grp2);
exec dbms_stats.gather_table_stats(user,'RTSPM_T',cascade=>true,method_opt=>'for all columns size 1')
 
-- Runner: execute one tagged statement N times with varying binds
create or replace procedure rtspm_run(p_sql varchar2, p_n number default 10) is
  v number;
  t number := dbms_utility.get_time;
begin
  for i in 1..p_n loop
    execute immediate p_sql into v using mod(i*7919,100000);
  end loop;
  dbms_output.put_line('elapsed cs: '||(dbms_utility.get_time - t));
end;
/
 
-- Helper query: plans and baselines for the tagged statements
-- (re-use after every step)
-- select sql_id, child_number, plan_hash_value, executions,
--        round(elapsed_time/greatest(executions,1)/1000,2) avg_ms,
--        sql_plan_baseline, substr(sql_text,1,60) sql_text
-- from   v$sql where sql_text like 'select /* RTSPM_TC%' order by sql_id, child_number;
 
-- =====================================================================
-- PHASE 1 - establish good plans and let ASTS capture them
-- =====================================================================
-- TC1 good plan: INDEX RANGE SCAN on RTSPM_GRP_IX
exec rtspm_run('select /* RTSPM_TC1 */ sum(val) from rtspm_t where grp = :g')
 
-- TC2 baseline plan: FULL scan (no index on UK yet)
exec rtspm_run('select /* RTSPM_TC2 */ sum(val) from rtspm_t where uk = :g', 3)
 
-- Show the plans (expect TC1 index, TC2 full)
select sql_id, plan_hash_value, executions,
       round(elapsed_time/greatest(executions,1)/1000,2) avg_ms,
       substr(sql_text,1,60) sql_text
from   v$sql where sql_text like 'select /* RTSPM_TC%';
 
-- WAIT until ASTS has captured TC1 and TC2 (poll every few minutes)
select sql_id, plan_hash_value, executions, substr(sql_text,1,60) sql_text
from   dba_sqlset_statements
where  sqlset_owner = 'SYS' and sqlset_name = 'SYS_AUTO_STS'
and    sql_text like 'select /* RTSPM_TC%';
-- Continue to PHASE 2 only when both rows are present.
-- If nothing after 30 min: check 'Auto STS Capture Task' status (step 0).
 
-- =====================================================================
-- PHASE 2
-- =====================================================================
 
-- ---------------------------------------------------------------------
-- TC1 - Regression detected and repaired in the foreground
-- Make the optimizer believe GRP has 1 distinct value -> it picks a
-- FULL scan, which is really ~100x slower. no_invalidate=>false forces
-- a hard parse on next execution.
-- ---------------------------------------------------------------------
exec dbms_stats.set_column_stats(user,'RTSPM_T','GRP', distcnt=>1, density=>1, no_invalidate=>false)
 
exec rtspm_run('select /* RTSPM_TC1 */ sum(val) from rtspm_t where grp = :g')
-- EXPECTED: first execution(s) use the new FULL plan, real-time SPM
--           compares it with the ASTS plan, then reinstates the index plan.
 
select sql_handle, plan_name, origin, enabled, accepted, reproduced,
       created, last_verified, foreground_last_verified
from   dba_sql_plan_baselines
where  sql_text like 'select /* RTSPM_TC1%'
order  by created;
-- EXPECTED: origin FOREGROUND-CAPTURE
--           index plan  ACCEPTED=YES
--           full plan   ACCEPTED=NO
-- (If FOREGROUND_LAST_VERIFIED raises ORA-00904, drop it - column name
--  differs between builds.)
 
-- Evidence of the decision (plans compared + their statistics)
select plan_name, accepted, notes
from   dba_sql_plan_baselines
where  sql_text like 'select /* RTSPM_TC1%';
 
-- Confirm the running cursor now uses the baseline
select sql_id, child_number, plan_hash_value, executions,
       round(elapsed_time/greatest(executions,1)/1000,2) avg_ms, sql_plan_baseline
from   v$sql where sql_text like 'select /* RTSPM_TC1%';
-- EXPECTED: newest child has SQL_PLAN_BASELINE populated, index plan hash
 
-- ---------------------------------------------------------------------
-- TC2 - A better new plan is not blocked
-- ---------------------------------------------------------------------
create index rtspm_uk_ix on rtspm_t(uk);
 
exec rtspm_run('select /* RTSPM_TC2 */ sum(val) from rtspm_t where uk = :g', 3)
 
select sql_id, child_number, plan_hash_value, executions,
       round(elapsed_time/greatest(executions,1)/1000,2) avg_ms, sql_plan_baseline
from   v$sql where sql_text like 'select /* RTSPM_TC2%';
select plan_name, origin, enabled, accepted
from   dba_sql_plan_baselines where sql_text like 'select /* RTSPM_TC2%';
-- EXPECTED: new INDEX plan in use, faster; if a baseline is created the
--           index plan is ACCEPTED. The old FULL plan must NOT be forced back.
 
-- ---------------------------------------------------------------------
-- TC3 - No ASTS history -> no protection
-- Good plan runs, then is broken BEFORE the next ASTS capture.
-- Run these steps back to back (well inside the 15 min interval).
-- ---------------------------------------------------------------------
exec rtspm_run('select /* RTSPM_TC3 */ sum(val) from rtspm_t where grp2 = :g')
-- (good plan, index on GRP2)
 
exec dbms_stats.set_column_stats(user,'RTSPM_T','GRP2', distcnt=>1, density=>1, no_invalidate=>false)
 
exec rtspm_run('select /* RTSPM_TC3 */ sum(val) from rtspm_t where grp2 = :g')
 
select plan_name, origin, accepted
from   dba_sql_plan_baselines where sql_text like 'select /* RTSPM_TC3%';
-- EXPECTED: no rows - regression stays in place (FULL scan, slow)
select sql_id, child_number, plan_hash_value,
       round(elapsed_time/greatest(executions,1)/1000,2) avg_ms
from   v$sql where sql_text like 'select /* RTSPM_TC3%';
 
-- ---------------------------------------------------------------------
-- TC4 - Accepted plan becomes non-reproducible
-- Drop the index behind TC1's accepted baseline plan.
-- ---------------------------------------------------------------------
drop index rtspm_grp_ix;
 
exec rtspm_run('select /* RTSPM_TC1 */ sum(val) from rtspm_t where grp = :g', 3)
-- EXPECTED: statement runs (no error), optimizer falls back to a FULL plan
 
select plan_name, accepted, reproduced
from   dba_sql_plan_baselines where sql_text like 'select /* RTSPM_TC1%';
-- EXPECTED / RECORD: index plan REPRODUCED = NO after next parse
 
-- =====================================================================
-- Monitoring query for the health check (daily)
-- Number of regressions real-time SPM repaired, per day
-- =====================================================================
select trunc(created) day, count(*) foreground_baselines
from   dba_sql_plan_baselines
where  origin = 'FOREGROUND-CAPTURE'
group  by trunc(created) order by 1;
 
-- =====================================================================
-- Cleanup
-- =====================================================================
declare
  n pls_integer;
begin
  for r in (select distinct sql_handle from dba_sql_plan_baselines
            where sql_text like 'select /* RTSPM_TC%') loop
    n := dbms_spm.drop_sql_plan_baseline(sql_handle => r.sql_handle);
  end loop;
end;
/
drop procedure rtspm_run;
drop table rtspm_t purge;
-- Restore previous setting if it was not AUTO:
-- exec dbms_spm.configure('AUTO_SPM_EVOLVE_TASK','<previous value>')
