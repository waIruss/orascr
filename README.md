-- =====================================================================
-- Schema-Level Privileges - test script
-- Target  : Oracle 23ai / 26ai, inside one PDB
-- Run as  : admin account with CREATE USER, CREATE ROLE, GRANT ANY SCHEMA
--           (no SYSDBA needed)
-- Sessions: ADMIN plus logins as APP1, APP2, DEV1, SEC1.
--           In SQL Developer use a separate connection per user.
--
-- Test cases
--   TC1  Read access to one schema, incl. objects created AFTER the grant
--   TC2  Scope boundary (negative): other schema, other privileges,
--        dictionary visibility
--   TC3  Developer DML + DDL on an app schema through a role
--        (= access model option A without ANY-level privileges)
--   TC4  Who can grant, and revoke behaviour
-- =====================================================================

-- =====================================================================
-- ADMIN : Setup
-- =====================================================================
drop user app1 cascade;
drop user app2 cascade;
drop user dev1 cascade;
drop user sec1 cascade;
drop role dev_app_r;

create user app1 identified by "Test#App1_2026" quota 50m on users;
create user app2 identified by "Test#App2_2026" quota 50m on users;
create user dev1 identified by "Test#Dev1_2026";
create user sec1 identified by "Test#Sec1_2026";
grant create session, create table, create sequence, create procedure to app1, app2;
grant create session to dev1, sec1;

-- APP1 objects (connect as APP1)
-- create table orders  (id number primary key, amount number);
-- create table clients (id number primary key, name varchar2(50));
-- insert into orders  values (1, 100);
-- insert into clients values (1, 'ACME');
-- commit;

-- APP2 objects (connect as APP2)
-- create table secrets (id number, val varchar2(50));
-- insert into secrets values (1, 'not for dev1');
-- commit;

-- =====================================================================
-- TC1 - Read access to one schema, including future objects
-- Expected: DEV1 reads every APP1 table, also one created after the grant
-- =====================================================================
-- APP1 (owner grants on own schema, no special privilege needed):
grant select any table on schema app1 to dev1;

-- DEV1:
select * from app1.orders;          -- EXPECTED: 1 row
select * from app1.clients;         -- EXPECTED: 1 row

-- APP1: create a NEW table after the grant
create table invoices (id number, total number);
insert into invoices values (1, 500);
commit;

-- DEV1: no new grant issued
select * from app1.invoices;        -- EXPECTED: 1 row  <- key difference vs object grants

-- DEV1: what the session actually holds
select * from session_schema_privs;
-- EXPECTED: SELECT ANY TABLE / APP1

-- Optional check, record result: is READ ANY TABLE schema-grantable?
-- (READ does not allow SELECT ... FOR UPDATE, so it is the safer choice
--  for a read-only role)
-- APP1: grant read any table on schema app1 to dev1;

-- =====================================================================
-- TC2 - Scope boundary (negative test)
-- Expected: nothing outside APP1 and nothing beyond SELECT
-- =====================================================================
-- DEV1:
select * from app2.secrets;                         -- EXPECTED: ORA-00942
update app1.orders set amount = 0 where id = 1;     -- EXPECTED: ORA-01031
delete from app1.clients;                           -- EXPECTED: ORA-01031
create table app1.hack (x number);                  -- EXPECTED: ORA-01031

-- Side effect worth recording: SELECT ANY TABLE also allows row locking
select * from app1.orders for update;               -- EXPECTED: works (locks the row)
rollback;

-- ADMIN: where the grant is (and is NOT) visible
select * from dba_sys_privs  where grantee = 'DEV1';                   -- EXPECTED: CREATE SESSION only
select * from dba_tab_privs  where grantee = 'DEV1';                   -- EXPECTED: no rows
select * from dba_schema_privs where grantee = 'DEV1';                 -- EXPECTED: SELECT ANY TABLE / APP1
-- Audit queries that read only DBA_SYS_PRIVS / DBA_TAB_PRIVS miss this grant.

-- =====================================================================
-- TC3 - Developer DML + DDL on an app schema via a role
-- Expected: full DML and table DDL inside APP1, nothing in APP2,
--           no instance-wide ANY privilege involved
-- =====================================================================
-- ADMIN:
create role dev_app_r;
grant select any table, insert any table, update any table, delete any table
  on schema app1 to dev_app_r;
grant create any table, alter any table, drop any table
  on schema app1 to dev_app_r;
grant select any sequence on schema app1 to dev_app_r;
grant dev_app_r to dev1;

-- DEV1: RECONNECT (role is enabled at logon), then:
select * from session_schema_privs order by privilege;
-- EXPECTED: role-derived privileges listed for APP1

insert into app1.orders values (2, 200);            -- EXPECTED: works
update app1.orders set amount = 250 where id = 2;   -- EXPECTED: works
commit;

create table app1.dev_test (id number);             -- EXPECTED: works, owned by APP1
alter table app1.dev_test add (note varchar2(20));  -- EXPECTED: works
create table app2.dev_test (id number);             -- EXPECTED: ORA-01031

-- Aliasing check: unqualified index name on an APP1 table.
-- Index would be created in DEV1's own schema - record what happens.
create index dev_test_ix on app1.dev_test(id);
-- RECORD: error (ORA-01031 / ORA-01950 quota) or created in DEV1 schema?
create index app1.dev_test_ix on app1.dev_test(id);
-- RECORD: does the schema grant cover CREATE INDEX, or is
--         CREATE ANY INDEX ON SCHEMA APP1 needed as well?

drop table app1.dev_test purge;                     -- EXPECTED: works

-- ADMIN: confirm ownership landed in APP1 and nothing was created in DEV1
select owner, object_name, object_type from dba_objects
where  owner in ('APP1','DEV1') and created > sysdate - 1/24
order  by owner, object_name;

-- =====================================================================
-- TC4 - Who can grant, and revoke behaviour
-- Expected: owner grants freely; a third user needs GRANT ANY SCHEMA;
--           revoke takes effect for the grantee
-- =====================================================================
-- SEC1 (no extra privileges):
grant select any table on schema app2 to dev1;      -- EXPECTED: ORA-01031

-- ADMIN:
grant grant any schema to sec1;

-- SEC1 (reconnect not needed for a direct system privilege):
grant select any table on schema app2 to dev1;      -- EXPECTED: works
-- DEV1:
select * from app2.secrets;                         -- EXPECTED: 1 row

-- Revoke - direct grant, DEV1 session left OPEN
-- APP2:
revoke select any table on schema app2 from dev1;
-- DEV1 (same session, no reconnect):
select * from app2.secrets;
-- RECORD: immediate ORA-00942, or still readable until reconnect?

-- Revoke - via role, DEV1 session left OPEN
-- ADMIN:
revoke select any table on schema app1 from dev_app_r;
revoke select any table on schema app1 from dev1;   -- remove TC1 direct grant too
-- DEV1 (same session):
select * from app1.orders;
-- RECORD: behaviour in the open session vs after reconnect

-- =====================================================================
-- ADMIN : Optional - privilege analysis (EE, no extra license)
-- Shows which schema privileges were actually USED, for right-sizing.
-- =====================================================================
-- exec dbms_privilege_capture.create_capture('SPRIV_CAP', type => dbms_privilege_capture.g_database);
-- exec dbms_privilege_capture.enable_capture('SPRIV_CAP');
--   ... run TC1/TC3 statements as DEV1 ...
-- exec dbms_privilege_capture.disable_capture('SPRIV_CAP');
-- exec dbms_privilege_capture.generate_result('SPRIV_CAP');
-- select * from dba_used_schema_privs   where capture = 'SPRIV_CAP';
-- select * from dba_unused_schema_privs where capture = 'SPRIV_CAP';
-- exec dbms_privilege_capture.drop_capture('SPRIV_CAP');

-- =====================================================================
-- ADMIN : Cleanup
-- =====================================================================
-- drop user app1 cascade;
-- drop user app2 cascade;
-- drop user dev1 cascade;
-- drop user sec1 cascade;
-- drop role dev_app_r;
