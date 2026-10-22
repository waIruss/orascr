Real-Time SQL Plan Management — feature evaluation

Feature: Real-Time SQL Plan Management (real-time SPM) Introduced: Oracle Database 23ai, carried into 26ai License: Oracle states it is licensed for 23ai Enterprise Edition. Confirm against the 26ai Licensing Information User Manual before production use. On OCI Base Database Service, the Diagnostics and Tuning Packs are included from the EE tier anyway. Scope: database-level, configured per PDB. No Data Guard or RAC dependency. Companion script: rtspm_test.sql

1. What it is

A plan regression happens when a statement that ran well suddenly gets a worse execution plan, typically after a statistics refresh, a parameter change, an upgrade or a new index. In 19c the usual fixes are manual: find the old plan in AWR, then load a baseline or SQL profile, after the incident has already happened. Automatic SPM in 19c ran as a nightly background task and was restricted to Exadata and Autonomous platforms.

Real-time SPM moves detection into the foreground, at the moment the new plan runs:

History. The Automatic SQL Tuning Set (ASTS, SYS_AUTO_STS) periodically captures SQL statements, plans and their performance from the cursor cache. By default it runs every 15 minutes.
Detection. At hard parse, the optimizer notices that it has produced a plan not seen before for a statement that has a known-good plan in the ASTS.
Verification. The new plan executes once. Its performance is compared with the ASTS reference plan by the session that ran it.
Correction. If the new plan is worse, both plans are stored as SQL plan baselines: the old one accepted, the new one rejected. Subsequent executions use the good plan. If the new plan is better, it is kept.
Reverse verification. If the optimizer later believes, based on cost, that a rejected plan is now best, it re-checks performance and can reinstate that plan.

Real-time SPM handles only regressions caused by plan changes. It does not help with data growth, contention or a plan that was always bad.

Configuration
Item	Setting
Enable	DBMS_SPM.CONFIGURE('AUTO_SPM_EVOLVE_TASK','AUTO')
Disable	DBMS_SPM.CONFIGURE('AUTO_SPM_EVOLVE_TASK','OFF')
Prerequisite	OPTIMIZER_CAPTURE_SQL_PLAN_BASELINES = FALSE (baseline auto-capture is a different mechanism)
Non-autonomous systems	SYS_AUTO_SPM_EVOLVE_TASK parameter ACCEPT_PLANS = TRUE, set as SYS in the PDB
Privilege	ADMINISTER SQL MANAGEMENT OBJECT
Observability
Source	What it shows
DBA_SQL_PLAN_BASELINES.ORIGIN = 'FOREGROUND-CAPTURE'	baselines created by real-time SPM
DBA_SQL_PLAN_BASELINES.NOTES	XML: plans compared and their execution statistics
DBA_SQL_PLAN_BASELINES.FOREGROUND_LAST_VERIFIED	last foreground verification
V$SQL.SQL_PLAN_BASELINE	which cursor is running under a baseline
DBA_SQLSET_STATEMENTS (SYS_AUTO_STS)	what history is available for comparison
DBA_AUTOTASK_SCHEDULE_CONTROL	status of the Auto STS Capture Task and Auto SPM Task
Fit criteria

Real-time SPM works for repeatable SQL with bind variables, which is typical of OLTP and batch applications. Highly dynamic or literal SQL is out of scope, because each statement is new and has no history to compare against.

2. Test environment
Oracle 23ai or 26ai EE, one PDB
Table RTSPM_T: 1M rows, about 220 MB. Columns GRP and GRP2 have 10 rows per value and are indexed. Column UK is unique and not indexed at the start.
Regressions are induced with DBMS_STATS.SET_COLUMN_STATS(distcnt=>1, no_invalidate=>false). The optimizer then believes the predicate returns every row, picks a full scan that is really about 100× slower, and the next execution hard parses.
Statements run through EXECUTE IMMEDIATE with binds, so the SQL text and the /* RTSPM_TCx */ tag stay identical on every run.
Two-phase timeline. Phase 1 runs the good plans and then waits until the ASTS has captured them, at least one capture interval (about 15 minutes). Phase 2 breaks the plans. Phase 2 is only meaningful once the statements are visible in SYS_AUTO_STS.
3. Test cases
ID	What it proves	Action	Expected	Pass criteria
TC1	Core behaviour: a regression is repaired in the foreground	fake statistics flip the index plan to a full scan	the first execution(s) run the bad plan, then the good plan is reinstated automatically	FOREGROUND-CAPTURE baseline: index plan accepted, full plan rejected; later executions back at index speed
TC2	Safety: an improvement is not blocked	create an index that makes a faster plan available	the new plan is used and kept	new index plan in use; the old full plan is not forced back
TC3	Limitation: protection needs ASTS history	the good plan is broken before the next ASTS capture	the regression persists; no baseline is created	no FOREGROUND-CAPTURE row; full scan still running
TC4	Safety: the accepted plan becomes impossible	drop the index behind TC1's accepted plan	the statement still runs with a fallback plan; no errors	statement succeeds; REPRODUCED behaviour recorded
Results template
ID	Result	Avg ms before	Avg ms after	Baseline rows (origin / accepted)	Notes
Pre		—	—	—	AUTO enabled? ASTS task enabled?
TC1					how many bad executions before the switch
TC2					baseline created or not
TC3					
TC4					REPRODUCED value
4. Evaluation criteria
Criterion	Weight	How measured
Repairs regressions without DBA action	high	TC1
Does not hold back better plans	high	TC2
Fails safe when a baseline plan is unusable	high	TC4
Understood coverage gap	medium	TC3, the ASTS capture window
Evidence trail for post-incident review	medium	NOTES XML and ORIGIN in TC1
Operational cost	medium	ASTS and SPM tasks run in the background; storage in SYSAUX
5. Operational fit

Where it helps

Post-statistics-gather regressions. This is the most common cause of "it was fast yesterday" incidents. TC1 reproduces exactly this pattern.
Upgrades and patching. An upgrade from 19c changes optimizer behaviour across the board. With ASTS history captured before the upgrade, real-time SPM reverts the individual statements whose plans got worse.
Shorter incident time. The exposure shrinks from hours (detect, investigate, load a baseline manually) to one or a few bad executions.
Health-check metric. A daily count of FOREGROUND-CAPTURE baselines measures how many plan regressions occurred and were repaired. That is a trend metric that does not exist in 19c without AWR analysis. The query is in the script.

Limits and risks

No history, no protection. New SQL, or SQL whose good plan was never captured, is not protected (TC3). After the feature is enabled, the ASTS needs time to accumulate history before it gives coverage.
The first bad execution still happens. The new plan must run at least once to be measured. A single catastrophic execution, such as a long batch query, still completes or must be cancelled before the switch.
Plan-change regressions only. It does nothing for data growth, locking or resource shortages.
Data skew. Skew-sensitive statements are left to adaptive cursor sharing, so some of them can regress until ACS adjusts.
Baselines accumulate. Accepted plans pin behaviour. Periodic review of old FOREGROUND-CAPTURE baselines is needed so they don't block better plans after schema or data changes. The Auto SPM Task evolve process covers part of this.
Interaction with manual SPM and SQL profiles. Existing baselines and profiles in the fleet need an inventory before enabling, to avoid conflicting fixes.
6. Summary

Real-time SPM detects plan regressions at the moment the new plan executes. It compares the plan with the known-good plan captured in the Automatic SQL Tuning Set, and if the new plan is worse it reinstates the good plan as an accepted SQL plan baseline. No DBA action is needed. It is configured per PDB with one DBMS_SPM.CONFIGURE call and is licensed with 23ai Enterprise Edition (confirm against the 26ai Licensing Information User Manual).

For a DBA team the value is shorter regression incidents. The usual "stats gather broke a query" pattern is repaired after one or a few bad executions instead of after manual investigation. It also produces a natural health-check metric: the count of repaired regressions per day. Its coverage depends on ASTS history, so it protects established, repeatable SQL and not new or ad-hoc statements. It also cannot prevent the first bad execution.

Recommended position: adopt for OLTP and batch PDBs with repeatable bind-variable SQL. Enable it well before major changes such as 19c→26ai upgrades or statistics policy changes, so the ASTS has history to compare against. Add the FOREGROUND-CAPTURE count to the daily health check, and review accumulated baselines periodically.
