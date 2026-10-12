-- =====================================================================
-- Automatic Transaction Rollback (Priority Transactions) - test script
-- Target  : Oracle 23ai / 26ai Enterprise Edition
-- Needs   : test schema + ALTER SYSTEM at PDB level (or a DBA to set the
--           system parameters once)
-- Sessions: THREE separate connections are required
--             S0 = admin (parameters, monitoring)
--             S1 = blocker
--             S2 = waiter
--           SQL Developer: open S1/S2 as UNSHARED worksheets
--           (Ctrl+Shift+N). A shared worksheet runs everything in one
--           session and no lock conflict will ever occur.
--           SQL*Plus / SQLcl in separate terminals is the safest option.
--
-- Test cases
--   TC1  LOW blocker vs HIGH waiter, ROLLBACK mode   - core behaviour
--   TC2  HIGH blocker vs HIGH waiter                 - negative test
--   TC3  TRACK mode                                  - safe rollout path
--   TC4  Forgotten ad-hoc session, multi-row         - real-world case
-- =====================================================================

-- =====================================================================
-- S0 : Preconditions
-- =====================================================================
select banner_full from v$version;

select name, value, isdefault, ispdb_modifiable, issys_modifiable
from   v$parameter
where  name in ('txn_priority',
                'priority_txns_mode',
                'priority_txns_high_wait_target',
                'priority_txns_medium_wait_target');
-- Record defaults and whether the parameters can be set inside a PDB.
-- If ISPDB_MODIFIABLE = FALSE or a lockdown profile blocks ALTER SYSTEM,
-- note it - it decides whether DBaaS tenants can use the feature at all.

-- Baseline counters
select name, value from v$sysstat
where  name like 'txns rollback%' or name like 'txns track mode%'
order  by name;

-- =====================================================================
-- S0 : Setup
-- =====================================================================
drop table atr_accounts purge;
create table atr_accounts (
  acc_id   number primary key,
  balance  number(12,2) not null,
  upd_by   varchar2(30)
);
insert into atr_accounts select level, 1000, null from dual connect by level <= 10;
commit;

-- Short target so the test runs in seconds
alter system set priority_txns_mode             = 'ROLLBACK' scope=memory;
alter system set priority_txns_high_wait_target = 10         scope=memory;

-- =====================================================================
-- TC1 - LOW blocker, HIGH waiter, ROLLBACK mode
-- Expected: after ~10 s S1's transaction is rolled back, S2 proceeds,
--           S1's session stays connected and gets ORA-63300
-- =====================================================================
-- S1:
alter session set txn_priority = LOW;
update atr_accounts set balance = balance - 100, upd_by = 'S1_LOW' where acc_id = 1;
-- leave uncommitted

-- S0: confirm priority is recorded on the transaction
select s.sid, s.username, t.txn_priority, t.priority_txns_wait_target
from   v$transaction t join v$session s on s.taddr = t.addr;

-- S2:
alter session set txn_priority = HIGH;
set timing on
update atr_accounts set balance = balance + 100, upd_by = 'S2_HIGH' where acc_id = 1;
-- EXPECTED: hangs ~10 s, then "1 row updated"

-- S0: while S2 waits (inside the 10 s window)
select sid, blocking_session, event, seconds_in_wait
from   v$session where blocking_session is not null;

-- S2:
commit;

-- S1: any next statement
select count(*) from atr_accounts;
-- EXPECTED: ORA-63300 - transaction was automatically rolled back
rollback;                             -- acknowledge; mandatory
select count(*) from atr_accounts;    -- works again, same session

-- S0: verify
select acc_id, balance, upd_by from atr_accounts where acc_id = 1;
-- EXPECTED: balance 1100, upd_by S2_HIGH  (S1's -100 is gone)
select name, value from v$sysstat where name like 'txns rollback%';
-- EXPECTED: 'txns rollback priority_txns_high_wait_target' +1

-- =====================================================================
-- TC2 - HIGH blocker, HIGH waiter   (negative test)
-- Expected: classic lock wait, blocker never rolled back
-- =====================================================================
-- S1:
alter session set txn_priority = HIGH;
update atr_accounts set upd_by = 'S1_HIGH' where acc_id = 3;
-- S2:
alter session set txn_priority = HIGH;
update atr_accounts set upd_by = 'S2_HIGH' where acc_id = 3;
-- EXPECTED: waits indefinitely (enq: TX - row lock contention)

-- S0: after > 30 s (3x target)
select name, value from v$sysstat where name like 'txns rollback%';
-- EXPECTED: no change since TC1

-- Release:
-- S1: commit;
-- S2: commit;   -- S2's update completes only after S1 commits

-- =====================================================================
-- TC3 - TRACK mode (measure without acting)
-- Expected: no rollback, track counter increments
-- =====================================================================
-- S0:
alter system set priority_txns_mode = 'TRACK' scope=memory;
-- S1:
alter session set txn_priority = LOW;
update atr_accounts set upd_by = 'S1_LOW' where acc_id = 5;
-- S2:
alter session set txn_priority = HIGH;
update atr_accounts set upd_by = 'S2_HIGH' where acc_id = 5;
-- EXPECTED: still waiting past the 10 s target

-- S0: after ~15 s
select name, value from v$sysstat
where  name like 'txns track mode%' or name like 'txns rollback%';
-- EXPECTED: 'txns track mode priority_txns_high_wait_target' +1
--           'txns rollback ...' unchanged

-- Release:
-- S1: commit;
-- S2: commit;
-- S0:
alter system set priority_txns_mode = 'ROLLBACK' scope=memory;

-- =====================================================================
-- TC4 - Forgotten ad-hoc session (real-world pattern)
-- Developer session (LOW) changes several rows and goes idle;
-- application session at DEFAULT priority must finish.
-- Expected: the WHOLE blocker transaction is undone, not just the
--           contended row
-- =====================================================================
-- S1 (simulates SQL Developer left open):
alter session set txn_priority = LOW;
update atr_accounts set balance = 0 where acc_id between 6 and 10;
-- (no commit, idle)

-- S2 (application - no ALTER SESSION, default priority = HIGH):
-- reconnect S2 first, or: alter session set txn_priority = HIGH;
update atr_accounts set balance = balance + 1 where acc_id = 8;
-- EXPECTED: proceeds after ~10 s
commit;

-- S0:
select acc_id, balance from atr_accounts where acc_id between 6 and 10 order by 1;
-- EXPECTED: 1000, 1000, 1001, 1000, 1000

-- S1:
rollback;   -- acknowledge ORA-63300

-- Deployment note (not a test): ad-hoc users can be classified LOW
-- without app change via an AFTER LOGON trigger:
--   if sys_context('USERENV','SESSION_USER') in ('ADHOC_USER') then
--     execute immediate 'alter session set txn_priority = LOW';
--   end if;

-- =====================================================================
-- S0 : Cleanup
-- =====================================================================
alter system reset priority_txns_high_wait_target scope=memory;
alter system reset priority_txns_mode             scope=memory;
drop table atr_accounts purge;
