4. Evolving new plans

Once a statement has a baseline, new plans the optimizer finds are only recorded, not used (§3.1). Evolving is the step that decides whether one of them should be used: the unaccepted plan is test-run, compared with the accepted plan, and accepted if it performs better.

By default, Oracle does this automatically every night. The task SYS_AUTO_SPM_EVOLVE_TASK runs in the maintenance window (as part of the sql tuning advisor autotask client), for up to an hour. Because ACCEPT_PLANS = TRUE by default, every plan that tests better is accepted on the spot, without anyone reviewing it.

What that means in practice:

Good: baselines don't go stale. When data or statistics change and a better plan appears, it's taken into use after being tested, with no DBA effort.
Risk: a statement you deliberately stabilized with a baseline can get a different plan overnight, outside any change process.
Risk: the test run uses the bind values stored with the plan, so the new plan is only proven better for those values. For other values it can be worse.
Note: if the sql tuning advisor autotask client is disabled (often done for Tuning Pack licensing), this task doesn't run either.

Recommendation:

Critical, change-controlled production: set ACCEPT_PLANS = FALSE. The task keeps testing plans and reporting what it found, but nothing changes until a DBA reviews the report and accepts a plan through the change process.
Other systems: keep the default. A plan is only accepted after it tested better, which is a reasonable safeguard.
Statements that must not change at all: use FIXED = YES (with a review date) rather than relying on this setting.
sql
-- Current setting
SELECT parameter_value
FROM   dba_advisor_parameters
WHERE  task_name = 'SYS_AUTO_SPM_EVOLVE_TASK' AND parameter_name = 'ACCEPT_PLANS';

-- Switch to report only
EXEC DBMS_SPM.SET_EVOLVE_TASK_PARAMETER('SYS_AUTO_SPM_EVOLVE_TASK', 'ACCEPT_PLANS', 'FALSE');

-- What the last run tested and recommended
SELECT DBMS_SPM.REPORT_AUTO_EVOLVE_TASK FROM dual;
5. Risks
Risk	What happens	Mitigation
Baseline silently not used	The plan can't be reproduced (index dropped or renamed, object changed, upgrade). The optimizer uses a normal plan; there's no error.	Monitor REPRODUCED = 'NO' and statements that have a baseline but run without it (§7)
SQL text changes	An application release changes the statement text, even a comment or a literal. It gets a new signature, and the baseline, patch or profile no longer matches.	Check after every release (§7); FORCE_MATCH profiles for literal variants
Pinned plan gets worse over time	Data grows and a fixed plan becomes slow. Nothing alerts, because the plan didn't change.	Review dates; FIXED only temporarily
Plans change unattended	Auto-accept brings in a plan that tested better for one set of bind values but is worse for others.	ACCEPT_PLANS = FALSE on critical systems; review the evolve report
Outdated estimates	A profile's scaling factors are fixed when it's created and become wrong as data changes.	Review profiles; prefer fixing statistics
Ignored hints	A SQL patch hint is invalid (alias, query block), so it's silently ignored.	+HINT_REPORT after creation; check the Note section
Several mechanisms on one statement	Profile, patch and baseline interact; nobody can tell which one is causing what.	One mechanism per statement
Forgotten fixes	Hundreds of undocumented objects accumulate; after an upgrade they can hold the optimizer to old plans that are now worse.	Inventory with ticket and review date; quarterly review
Plans purged	Baselines not used for 53 weeks (default retention) are purged automatically.	AUTOPURGE = NO for rarely run statements that must keep their plan
Licensing	SQL profiles (all of DBMS_SQLTUNE) need the Tuning Pack; loading plans from AWR uses the Diagnostics Pack.	Without the Tuning Pack, use baselines and patches only
6. Governance rules
Cause first. Every stabilization object has a ticket that names the root cause and why it can't be fixed directly (or by when it will be).
One mechanism per statement.
Documented: the ticket, reason and review date go into the object's description (DESCRIPTION attribute or parameter).
Reviewed quarterly: objects past their review date are either justified again or removed.
Checked after every application release, patch and upgrade: are the baselines still matched and reproduced (§7)?
Evolution policy set explicitly per system class (ACCEPT_PLANS, §4). The hourly Automatic SPM mode (19.22+, off by default) stays off unless deliberately piloted.
No SQL profiles without a Tuning Pack license, including imported or script-built profiles.
Baselines moved between databases with staging tables (DBMS_SPM.PACK_STGTAB_BASELINE / UNPACK_STGTAB_BASELINE). They are stored per PDB and travel with a PDB clone or plug-in.
7. Inventory and monitoring
sql
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

Expected result of the last query: no rows. Every row is a baseline that is no longer doing its job, usually because the plan can't be reproduced.

8. Review checklist
 Root cause analysed; stabilization justified in a ticket.
 The right tool for the situation (§2); one mechanism per statement.
 Description holds ticket, reason and review date.
 Plan verified after creation: the Note section shows the mechanism; for patches, the hint report is clean.
 Bad cursor purged so the fix takes effect.
 ACCEPT_PLANS set according to the system class; FIXED only with a review date.
 No SQL profiles on systems without a Tuning Pack license.
 Post-release and post-upgrade check of unused or unreproduced baselines.
 Quarterly inventory review.
9. Quick reference: common mistakes
Symptom	Cause
Baseline created, but the bad plan keeps running	Old cursor still in the cursor cache; purge it
Baseline exists, SQL_PLAN_BASELINE empty in V$SQL	Plan can't be reproduced (object changed) or text no longer matches
Fix stopped working after an application release	Statement text changed (comment, literal, formatting beyond case and spaces)
Plan changed overnight on a statement "pinned" with a baseline	Auto-evolve accepted a new plan (ACCEPT_PLANS = TRUE)
Fixed plan, slow months later	Data grew; nobody reviewed the fixed plan
SQL patch has no effect	Hint invalid or not fully qualified; check +HINT_REPORT
Profile works for one statement but not its literal variants	Created without FORCE_MATCH
License audit finding on SQL profiles	Profiles created or imported without a Tuning Pack license
Old fixes hurt after an upgrade	Undocumented stabilization objects never reviewed; plans tuned for the previous optimizer
Rarely run report lost its plan	Baseline unused for over a year was auto-purged; set AUTOPURGE = NO
