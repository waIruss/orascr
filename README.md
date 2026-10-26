3. The standard
Oracle-maintained schemas: zero invalid objects. Any invalid object there is an incident: recompile, and if it stays invalid, follow the component-specific MOS note.
Application schemas: zero unexplained invalid objects. Every remaining invalid object has an owner, a reason, and a ticket, or gets dropped once the owner confirms it's no longer used.
Record before, compare after. Take a snapshot of invalid objects before every deployment, patch, upgrade and Data Pump import; after the change and recompilation, compare (§5). Only new invalid objects are a result of the change.
Recompile right after the change, before users arrive. Run recompilation as part of the change window, so no user session pays the compile cost or waits on library cache locks.
Deploy code that changes packages outside business hours. If zero-downtime deployments of PL/SQL are needed, use Edition-Based Redefinition (EBR) instead of CREATE OR REPLACE on packages in use.
Deployment pipelines fail on new invalid objects. The comparison from rule 3 runs as a pipeline step; a new invalid object fails the deployment.
4. Listing invalid objects and finding the cause
sql
-- Summary per schema and type (application schemas)
SELECT owner, object_type, COUNT(*) AS invalid_count
FROM   dba_objects
WHERE  status = 'INVALID'
AND    oracle_maintained = 'N'
GROUP  BY owner, object_type
ORDER  BY owner, object_type;

-- Oracle-maintained schemas: should return no rows
SELECT owner, object_type, object_name, last_ddl_time
FROM   dba_objects
WHERE  status = 'INVALID'
AND    oracle_maintained = 'Y'
ORDER  BY owner, object_type, object_name;

-- Full list (application schemas), most recently changed first
SELECT owner, object_type, object_name, last_ddl_time
FROM   dba_objects
WHERE  status = 'INVALID'
AND    oracle_maintained = 'N'
ORDER  BY last_ddl_time DESC;

In a CDB, invalid objects are per container: run the checks in every PDB, or use CDB_OBJECTS from the root and group by CON_ID.

Finding out why an object is invalid:

sql
-- Compilation errors (populated after a compile attempt)
SELECT line, position, text
FROM   dba_errors
WHERE  owner = '&owner' AND name = '&object_name'
ORDER  BY sequence;

-- What the object depends on, and the state of each dependency
SELECT d.referenced_owner, d.referenced_name, d.referenced_type, o.status
FROM   dba_dependencies d
LEFT   JOIN dba_objects o
       ON  o.owner       = d.referenced_owner
       AND o.object_name = d.referenced_name
       AND o.object_type = d.referenced_type
WHERE  d.owner = '&owner' AND d.name = '&object_name'
ORDER  BY o.status NULLS FIRST;
-- STATUS NULL (or REFERENCED_TYPE = 'NON-EXISTENT') = the referenced object doesn't exist
-- STATUS INVALID = fix that object first; this one depends on it

If DBA_ERRORS is empty, the object hasn't been compiled since it was invalidated. Compile it once (§6), then check again.

5. Before/after comparison
sql
-- One-time setup
CREATE TABLE dba_admin.invalid_obj_snapshot (
  snap_label  VARCHAR2(64),
  snap_time   DATE,
  owner       VARCHAR2(128),
  object_type VARCHAR2(30),
  object_name VARCHAR2(128)
);

-- Before the change
INSERT INTO dba_admin.invalid_obj_snapshot
SELECT 'CHG1234_BEFORE', SYSDATE, owner, object_type, object_name
FROM   dba_objects
WHERE  status = 'INVALID';
COMMIT;

-- After the change and recompilation: objects that are newly invalid
SELECT owner, object_type, object_name
FROM   dba_objects
WHERE  status = 'INVALID'
MINUS
SELECT owner, object_type, object_name
FROM   dba_admin.invalid_obj_snapshot
WHERE  snap_label = 'CHG1234_BEFORE';

The result of the last query must be empty, or every row explained before the change is closed.

For database upgrades, Oracle provides its own version of this: the pre-upgrade step records invalid objects, and @?/rdbms/admin/utluiobj.sql after the upgrade lists objects that were valid before and are invalid now.

6. Recompiling
sql
-- Whole database, as SYS: recompiles all invalid objects in dependency order, in parallel.
-- Standard after patching, upgrades and large imports.
@?/rdbms/admin/utlrp.sql

-- One schema, only invalid objects, 4 parallel jobs (requires SYSDBA)
EXEC UTL_RECOMP.RECOMP_PARALLEL(4, 'APP');

-- One schema, serial. compile_all => FALSE is essential: the default (TRUE)
-- recompiles valid objects too, which invalidates their dependents
-- and discards package state for every connected session.
EXEC DBMS_UTILITY.COMPILE_SCHEMA(schema => 'APP', compile_all => FALSE);

-- Single objects
ALTER PACKAGE app.pkg_orders COMPILE BODY;   -- body only: the spec is what others depend on
ALTER PACKAGE app.pkg_orders COMPILE;        -- spec and body, when the spec is invalid
ALTER VIEW app.v_orders COMPILE;
ALTER TRIGGER app.trg_orders_biu COMPILE;
ALTER TYPE app.t_order COMPILE;
ALTER PUBLIC SYNONYM some_synonym COMPILE;

Notes:

When: recompile in the change window, not while the application is busy (§2 point 2).
Order matters: objects depend on each other, so a manual compile of one object can fail only because something it uses is still invalid. utlrp.sql and UTL_RECOMP handle the order. When compiling by hand, repeat until the count stops going down.
CDB: utlrp.sql must run in every container. Use catcon.pl to run it across all PDBs.
Parallel recompilation uses scheduler jobs, so JOB_QUEUE_PROCESSES must be greater than 0.
7. What to do with objects that stay invalid
Situation	Action
Compile error in application code	Owner team fixes the code; ticket until done
Referenced object dropped on purpose	Drop or rewrite the dependent object
Missing privilege	Grant it directly to the owning schema (not through a role, for PL/SQL)
Object no longer used	Confirm with the owner, then drop it (keep the DDL for rollback)
Public synonym pointing to a dropped object	Drop the synonym
Oracle-maintained object	Follow the component's MOS note; never drop or edit Oracle-maintained objects by hand
Known and accepted for a while	Document owner, reason, ticket and review date; it then no longer counts as "unexplained"
