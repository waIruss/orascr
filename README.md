
# SQL Plan Management and Plan Stabilization: Standards and Best Practices
 
## Purpose
 
This page defines when and how to stabilize execution plans with SQL plan baselines, SQL profiles and SQL patches, how new plans are evolved, and which risks come with each method.
 
**The standard in one sentence: fix the cause first (statistics, histograms, code); use a stabilization tool only when the cause can't be fixed in time or at all: a SQL plan baseline to lock in a known good plan, a SQL patch to add one targeted hint, a SQL profile (Tuning Pack only) to correct estimates. Use one mechanism per statement, document each one with a ticket and a review date, and keep plan evolution under deliberate control.**
 
Applies to Oracle Database 19c/23ai Enterprise Edition. Related pages: *Oracle SQL Hinting*, *Adaptive Plan Control*.
 
---
 
## 1. The three tools at a glance
 
| | SQL plan baseline | SQL profile | SQL patch |
|---|---|---|---|
| **What it stores** | A complete plan (as a set of outline hints) | Mostly corrections to row estimates (`OPT_ESTIMATE`), sometimes other hints | The hints you specify |
| **Effect** | The optimizer must use one of the accepted plans | The optimizer gets better estimates and chooses the plan itself | The hints steer the optimizer; everything not hinted is still cost-based |
| **Can the plan still change?** | Only to another accepted plan, or if the plan can't be reproduced | Yes, as data changes | Yes, in the parts not covered by the hints |
| **Created from** | Cursor cache, AWR, SQL tuning set, staging table | SQL Tuning Advisor recommendation | `DBMS_SQLDIAG.CREATE_SQL_PATCH` |
| **Matches** | Exact statement text (case and spaces ignored) | Exact text, or with `FORCE_MATCH` also statements differing only in literals | Exact statement text |
| **New plans evolve** | Yes (evolve advisor) | No | No |
| **License** | Enterprise Edition | **Tuning Pack** | Enterprise Edition |
| **Best for** | Locking in a known good plan; protecting plans across upgrades | Systematic misestimates; SQL with literals | One targeted fix (e.g. switch off one feature for one statement); diagnostics |
 
All three work without changing application code, which is why they're the standard tools for vendor applications and incident fixes.
 
## 2. When to use which
 
| Situation | Tool | Why |
|---|---|---|
| A statement switched to a bad plan; the good plan is still in the cursor cache or in AWR | **Baseline** loaded with the good plan | Fastest exact fix: restores a plan that is known to work |
| No good plan exists anywhere; one or two hints would fix it | **SQL patch** | Adds only the needed hints; the rest of the plan stays cost-based |
| The optimizer misestimates rows and statistics can't fix it (and Tuning Pack is licensed) | **SQL profile** from SQL Tuning Advisor | Corrects the estimates; the optimizer can still adapt to data changes |
| The application uses literals instead of binds | **SQL profile** with `FORCE_MATCH` | Baselines and patches match only one literal variant |
| Upcoming upgrade or major change | **Baselines** captured before the change | Statements keep their known plans; new plans are evolved deliberately afterwards |
| A feature hurts one statement (e.g. adaptive plans) | **SQL patch** with `OPT_PARAM` | Switches it off for that statement only, instead of for the whole database |
| Diagnostics (row-source statistics, SQL monitoring) | **SQL patch** with `GATHER_PLAN_STATISTICS` or `MONITOR` | No code change; drop it afterwards |
 
## 3. How each tool works
 
### 3.1 SQL plan baselines
 
- Each statement has a **plan history**. Plans in it are either **accepted** (the optimizer may use them) or **unaccepted** (recorded but not used).
- Once a statement has a baseline, any new plan the optimizer finds is added as **unaccepted**. It's only used after it has been evolved (§4).
- With several accepted plans, the optimizer uses the cheapest one it can reproduce. A plan marked **`FIXED = YES`** is always preferred over non-fixed plans.
- The plan is stored as outline hints. If the optimizer can no longer reproduce it with those hints (an index was dropped or renamed, an object changed, an upgrade changed internal names), it **silently** falls back to a normal cost-based plan (§5).
```sql
-- Incident: restore the good plan from the cursor cache
DECLARE
  n PLS_INTEGER;
BEGIN
  n := DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE(
         sql_id          => '&sql_id',
         plan_hash_value => &good_plan_hash_value);
END;
/
 
-- The good plan is no longer cached: load it from AWR (reads AWR, so Diagnostics Pack)
DECLARE
  n PLS_INTEGER;
BEGIN
  n := DBMS_SPM.LOAD_PLANS_FROM_AWR(
         begin_snap   => &begin_snap,
         end_snap     => &end_snap,
         basic_filter => q'[sql_id = '&sql_id' AND plan_hash_value = &good_plan_hash_value]');
END;
/
 
-- Document it (ticket and review date in the description)
DECLARE
  n PLS_INTEGER;
BEGIN
  n := DBMS_SPM.ALTER_SQL_PLAN_BASELINE(
         sql_handle      => '&sql_handle',
         plan_name       => '&plan_name',
         attribute_name  => 'DESCRIPTION',
         attribute_value => 'INC12345: restored plan after regression; review 2027-01');
END;
/
```
 
If the bad plan is still running from the cursor cache, purge that cursor (`DBMS_SHARED_POOL.PURGE`) so the next execution is parsed again and picks up the baseline. Check the `Note` section of `DBMS_XPLAN.DISPLAY_CURSOR` for *"SQL plan baseline ... used for this statement"*.
 
### 3.2 SQL profiles
 
- Created by accepting a SQL Tuning Advisor recommendation (`DBMS_SQLTUNE.ACCEPT_SQL_PROFILE`).
- A typical profile doesn't fix the plan. It tells the optimizer by how much its row estimates are wrong (`OPT_ESTIMATE` scaling factors), and the optimizer then chooses a better plan itself.
- `FORCE_MATCH => TRUE` makes the profile apply to all statements that differ only in literal values.
- **Licensing:** all of `DBMS_SQLTUNE` requires the Tuning Pack, including manually built profiles (`IMPORT_SQL_PROFILE`, as used by scripts such as `coe_xfr_sql_profile.sql`). Without the Tuning Pack, use baselines or patches.
### 3.3 SQL patches
 
```sql
DECLARE
  p VARCHAR2(128);
BEGIN
  p := DBMS_SQLDIAG.CREATE_SQL_PATCH(
         sql_id      => '&sql_id',
         hint_text   => q'[FULL(@"SEL$1" "O"@"SEL$1")]',
         name        => 'PATCH_CHG1234',
         description => 'CHG1234: full scan of ORDERS; review 2027-01');
END;
/
 
-- Remove
EXEC DBMS_SQLDIAG.DROP_SQL_PATCH(name => 'PATCH_CHG1234');
```
 
- The hints follow the same rules as hints in code (see *Oracle SQL Hinting*): fully qualified query block names, aliases, and a hint set complete enough for its purpose.
- **An invalid hint is silently ignored.** After creating a patch, check the plan with `+HINT_REPORT` and confirm the `Note` section says *"SQL patch ... used for this statement"*.
### 3.4 How they combine
 
During a hard parse:
1. Hints from a SQL patch and a SQL profile are applied, and the optimizer produces its plan.
2. If the statement has accepted baseline plans, the baseline has the final say: the optimizer uses an accepted plan. If its own plan isn't one of them, that plan is added to the plan history as unaccepted.
So a profile or patch on a statement that already has a baseline only changes which *new* plans are found, not the plan that runs. Using several tools on one statement makes it hard to tell which one is causing what, so the standard allows **one mechanism per statement**.
 
## 4. Evolving new plans
 
**Evolving** means test-running an unaccepted plan from the plan history, comparing it with the accepted plan, and accepting it if it's better.
 
| Method | How | Pros | Cons |
|---|---|---|---|
| **Automatic, auto-accept** (default) | Nightly `SYS_AUTO_SPM_EVOLVE_TASK`, `ACCEPT_PLANS = TRUE` | No DBA effort; only plans that tested better are accepted; baselines don't go stale | Plans change without change control; the test runs use the bind values stored with the plan, so a plan proven better for those values may be worse for others; runs in the maintenance window and stops if the `sql tuning advisor` autotask client is disabled |
| **Automatic, report only** | Same task, `ACCEPT_PLANS = FALSE`; DBA reviews `DBMS_SPM.REPORT_AUTO_EVOLVE_TASK` | Same testing, but a person decides | Needs a regular review, otherwise better plans are never accepted |
| **Manual, with verification** | `DBMS_SPM.EVOLVE_SQL_PLAN_BASELINE(verify => 'YES', commit => 'NO')`, then again with `commit => 'YES'` | Fully controlled; the report is the evidence for the change | DBA time per statement |
| **Manual, without verification** | `verify => 'NO'`, or loading a plan directly | Fastest during an incident | Nothing is tested; you own the risk |
| **No evolution** | `FIXED = YES` | The plan can't change | The plan never improves; as data grows it can become slow without anyone noticing |
| **Automatic SPM** (19.22+) | `DBMS_SPM.CONFIGURE('AUTO_SPM_EVOLVE_TASK', 'ON')` | Finds and repairs regressions every hour, using AWR and SQL tuning sets | Least visible; off by default on-premises; try it on purpose, not by default |
 
**Recommendation:**
- **Critical, change-controlled production:** `ACCEPT_PLANS = FALSE`, with the evolve report reviewed weekly and plans accepted manually through the change process.
- **Other systems:** the default (`TRUE`) is acceptable, because a plan is accepted only after it tested better.
- **`FIXED = YES`:** only as a temporary incident measure, with a review date.
```sql
EXEC DBMS_SPM.SET_EVOLVE_TASK_PARAMETER('SYS_AUTO_SPM_EVOLVE_TASK', 'ACCEPT_PLANS', 'FALSE');
```
 
## 5. Risks
 
| Risk | What happens | Mitigation |
|---|---|---|
| **Baseline silently not used** | The plan can't be reproduced (index dropped or renamed, object changed, upgrade). The optimizer uses a normal plan; there's no error. | Monitor `REPRODUCED = 'NO'` and statements that have a baseline but run without it (§7) |
| **SQL text changes** | An application release changes the statement text, even a comment or a literal. It gets a new signature, and the baseline, patch or profile no longer matches. | Check after every release (§7); `FORCE_MATCH` profiles for literal variants |
| **Pinned plan gets worse over time** | Data grows and a fixed plan becomes slow. Nothing alerts, because the plan didn't change. | Review dates; `FIXED` only temporarily |
| **Plans change unattended** | Auto-accept brings in a plan that tested better for one set of bind values but is worse for others. | `ACCEPT_PLANS = FALSE` on critical systems; review the evolve report |
| **Outdated estimates** | A profile's scaling factors are fixed when it's created and become wrong as data changes. | Review profiles; prefer fixing statistics |
| **Ignored hints** | A SQL patch hint is invalid (alias, query block), so it's silently ignored. | `+HINT_REPORT` after creation; check the `Note` section |
| **Several mechanisms on one statement** | Profile, patch and baseline interact; nobody can tell which one is causing what. | One mechanism per statement |
| **Forgotten fixes** | Hundreds of undocumented objects accumulate; after an upgrade they can hold the optimizer to old plans that are now worse. | Inventory with ticket and review date; quarterly review |
| **Plans purged** | Baselines not used for 53 weeks (default retention) are purged automatically. | `AUTOPURGE = NO` for rarely run statements that must keep their plan |
| **Licensing** | SQL profiles (all of `DBMS_SQLTUNE`) need the Tuning Pack; loading plans from AWR uses the Diagnostics Pack. | Without the Tuning Pack, use baselines and patches only |
 
## 6. Governance rules
 
1. **Cause first.** Every stabilization object has a ticket that names the root cause and why it can't be fixed directly (or by when it will be).
2. **One mechanism per statement.**
3. **Documented:** the ticket, reason and review date go into the object's description (`DESCRIPTION` attribute or parameter).
4. **Reviewed quarterly:** objects past their review date are either justified again or removed.
5. **Checked after every application release, patch and upgrade:** are the baselines still matched and reproduced (§7)?
6. **Evolution policy set explicitly per system class** (`ACCEPT_PLANS`, §4); Automatic SPM stays off unless deliberately piloted.
7. **No SQL profiles without a Tuning Pack license**, including imported or script-built profiles.
8. **Baselines moved between databases with staging tables** (`DBMS_SPM.PACK_STGTAB_BASELINE` / `UNPACK_STGTAB_BASELINE`). They are stored per PDB and travel with a PDB clone or plug-in.
## 7. Inventory and monitoring
 
```sql
-- Baselines
SELECT sql_handle, plan_name, enabled, accepted, fixed, reproduced, autopurge,
       origin, created, last_executed, description
FROM   dba_sql_plan_baselines
ORDER  BY created DESC;
 
-- Profiles and patches
SELECT name, category, status, force_matching, created, description FROM dba_sql_profiles;
SELECT name, category, status, created, description FROM dba_sql_patches;
 
-- Which mechanism each cursor is using right now
SELECT sql_id, plan_hash_value, sql_plan_baseline, sql_profile, sql_patch
FROM   v$sql
WHERE  sql_plan_baseline IS NOT NULL OR sql_profile IS NOT NULL OR sql_patch IS NOT NULL;
 
-- Statements that have an accepted baseline but are running without it
SELECT s.sql_id, s.plan_hash_value, b.sql_handle, b.plan_name, b.reproduced
FROM   v$sql s
JOIN   dba_sql_plan_baselines b ON b.signature = s.exact_matching_signature
WHERE  b.enabled = 'YES' AND b.accepted = 'YES'
AND    s.sql_plan_baseline IS NULL;
```
 
Expected result of the last query: no rows. Every row is a baseline that is no longer doing its job, usually because the plan can't be reproduced.
 
## 8. Review checklist
 
- [ ] Root cause analysed; stabilization justified in a ticket.
- [ ] The right tool for the situation (§2); one mechanism per statement.
- [ ] Description holds ticket, reason and review date.
- [ ] Plan verified after creation: the `Note` section shows the mechanism; for patches, the hint report is clean.
- [ ] Bad cursor purged so the fix takes effect.
- [ ] `ACCEPT_PLANS` set according to the system class; `FIXED` only with a review date.
- [ ] No SQL profiles on systems without a Tuning Pack license.
- [ ] Post-release and post-upgrade check of unused or unreproduced baselines.
- [ ] Quarterly inventory review.
## 9. Quick reference: common mistakes
 
| Symptom | Cause |
|---|---|
| Baseline created, but the bad plan keeps running | Old cursor still in the cursor cache; purge it |
| Baseline exists, `SQL_PLAN_BASELINE` empty in `V$SQL` | Plan can't be reproduced (object changed) or text no longer matches |
| Fix stopped working after an application release | Statement text changed (comment, literal, formatting beyond case and spaces) |
| Plan changed overnight on a statement "pinned" with a baseline | Auto-evolve accepted a new plan (`ACCEPT_PLANS = TRUE`) |
| Fixed plan, slow months later | Data grew; nobody reviewed the fixed plan |
| SQL patch has no effect | Hint invalid or not fully qualified; check `+HINT_REPORT` |
| Profile works for one statement but not its literal variants | Created without `FORCE_MATCH` |
| License audit finding on SQL profiles | Profiles created or imported without a Tuning Pack license |
| Old fixes hurt after an upgrade | Undocumented stabilization objects never reviewed; plans tuned for the previous optimizer |
| Rarely run report lost its plan | Baseline unused for over a year was auto-purged; set `AUTOPURGE = NO` |
