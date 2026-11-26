AWR PLAYBOOK - knowledge file for the AWR Analyst agent
Scope: Oracle 19c and later, single instance and RAC, CDB/PDB, Exadata.
Thresholds below are typical starting points, not hard rules. Always weigh them against % of DB Time.
 
======================================================================
SECTION 1. GENERATING INPUT FOR THE AGENT
======================================================================
 
1.1 Text-format AWR (preferred: smaller, and parses cleanly)
  SQL*Plus:  @?/rdbms/admin/awrrpt.sql     -> report_type: text
  Specific DBID/instance:  @?/rdbms/admin/awrrpti.sql
  RAC global report:       @?/rdbms/admin/awrgrpt.sql
  Compare two periods:     @?/rdbms/admin/awrddrpt.sql
  Single SQL:              @?/rdbms/admin/awrsqrpt.sql
  ASH report:              @?/rdbms/admin/ashrpt.sql
  ADDM for a snap range:   @?/rdbms/admin/addmrpt.sql
 
  Without the interactive script:
    SET PAGESIZE 0 LINESIZE 1500 TRIMSPOOL ON HEADING OFF FEEDBACK OFF
    SPOOL awr_&&bid._&&eid..txt
    SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_TEXT(&dbid, &inst_num, &bid, &eid));
    SPOOL OFF
 
  Compare report (text):
    SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.AWR_DIFF_REPORT_TEXT(
      &dbid1, &inst1, &bid1, &eid1, &dbid2, &inst2, &bid2, &eid2));
 
1.2 Choosing the window
  - 15-60 minutes that tightly cover the problem. Long windows average away spikes.
  - For "it got slower": also take the same window on a good day and compare (awrddrpt).
  - Snapshot list:
      SELECT snap_id, instance_number, begin_interval_time, end_interval_time
      FROM dba_hist_snapshot
      WHERE begin_interval_time > SYSDATE - 2
      ORDER BY snap_id, instance_number;
 
1.3 PDB-level AWR (19c+)
  - Running awrrpt.sql inside a PDB prompts for the AWR data location: AWR_ROOT (CDB snapshots, PDB view) or AWR_PDB (PDB's own snapshots).
  - PDB snapshots require AWR_PDB_AUTOFLUSH_ENABLED=TRUE in the PDB (or manual DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT).
  - In a PDB-level report, Host CPU, OS Statistics and background waits are CDB-wide. A busy host with low PDB DB CPU = noisy neighbour PDBs.
 
======================================================================
SECTION 2. TEXT AWR SECTION TITLES (for parsing; titles vary slightly by version)
======================================================================
Report header / Report Summary / Top ADDM Findings by Average Active Sessions
Load Profile
Instance Efficiency Percentages (Target 100%)
Top 10 Foreground Events by Total Wait Time
Wait Classes by Total Wait Time
Host CPU
Instance CPU
IO Profile
Memory Statistics
Cache Sizes
Shared Pool Statistics
Time Model Statistics
Operating System Statistics
Foreground Wait Class
Foreground Wait Events
Background Wait Events
Wait Event Histogram
SQL ordered by Elapsed Time
SQL ordered by CPU Time
SQL ordered by User I/O Wait Time
SQL ordered by Gets
SQL ordered by Reads
SQL ordered by Physical Reads (UnOptimized)
SQL ordered by Executions
SQL ordered by Parse Calls
SQL ordered by Sharable Memory
SQL ordered by Version Count
SQL ordered by Cluster Wait Time
Complete List of SQL Text
Instance Activity Stats
IOStat by Function summary
IOStat by Filetype summary
Tablespace IO Stats
File IO Stats
Buffer Pool Advisory
PGA Aggr Summary
PGA Aggr Target Histogram
PGA Memory Advisory
Shared Pool Advisory
SGA Target Advisory
Enqueue Activity
Undo Segment Summary
Latch Activity
Latch Sleep Breakdown
Mutex Sleep Summary
Segments by Logical Reads
Segments by Physical Reads
Segments by Row Lock Waits
Segments by ITL Waits
Segments by Buffer Busy Waits
Segments by Global Cache Buffer Busy
Segments by CR Blocks Received
Segments by Current Blocks Received
Dictionary Cache Stats
Library Cache Activity
Resource Limit Stats
init.ora Parameters
RAC only:
Global Cache Load Profile
Global Cache Efficiency Percentages
Global Cache and Enqueue Services - Workload Characteristics
Global Cache and Enqueue Services - Messaging Statistics
Interconnect Ping Latency Stats
Interconnect Throughput by Client
Dynamic Remastering Stats
 
======================================================================
SECTION 3. WORKLOAD SANITY FORMULAS
======================================================================
AAS (average active sessions)   = DB Time (s) / Elapsed (s)
CPUs used by DB                 = "DB CPU(s)" per second in Load Profile
DB CPU share of host            = DB CPU (s) / (NUM_CPUS x Elapsed (s))
Host busy %                     = BUSY_TIME / (BUSY_TIME + IDLE_TIME)   (OS Statistics, centiseconds)
Run-queue pressure              = LOAD vs NUM_CPUS (LOAD > NUM_CPUS = processes queue for CPU)
Wait-bound vs CPU-bound         = DB CPU / DB Time (>~70% CPU-bound; <~30% wait-bound)
 
Notes:
- NUM_CPUS counts hardware threads. With SMT/hyper-threading, usable throughput is closer to cores x ~1.2-1.3 than to NUM_CPUS.
- On VMs, hypervisor steal time is invisible to Oracle. Symptom: log file sync much greater than log file parallel write, "gc ... congested" events, latch/mutex sleeps rising, while DB CPU looks moderate.
- AAS well below NUM_CPUS with no dominant event: the DB is mostly idle. The latency users feel is likely in the app tier, network or client (check SQL*Net roundtrips, user calls per execute).
 
======================================================================
SECTION 4. LATENCY BASELINES (average; always check the histogram tail)
======================================================================
Event                               NVMe/all-flash   SAN (SSD tier)   HDD / slow SAN   Exadata
db file sequential read             0.2-1 ms         1-3 ms           5-10 ms          n/a (see cell single block)
cell single block physical read     -                -                -                ~0.2-0.5 ms flash cache hit; much lower with XRMEM; several ms on disk
log file parallel write             0.3-1 ms         1-3 ms           >3 ms            sub-ms with flash log
log file sync                       ~1-2x log file parallel write in a healthy system
gc cr/current block 2-way           <0.5 ms on modern interconnect (25/100 GbE, RoCE, InfiniBand); 3-way slightly higher
control file parallel write         <~5 ms
Bimodal distributions (cache hit vs miss) make the average misleading; use the Wait Event Histogram section.
 
======================================================================
SECTION 5. WAIT EVENT REFERENCE
Format: meaning | typical causes | how to confirm | actions
======================================================================
 
DB CPU (not a wait)
  Meaning: time on CPU, including time queued for CPU that Oracle cannot see.
  Causes: high logical I/O (inefficient plans), hard parsing, PL/SQL loops, legitimately CPU-heavy workload.
  Confirm: SQL ordered by CPU Time and by Gets; gets/exec vs rows/exec; parse time in Time Model; OS LOAD vs NUM_CPUS.
  Actions: fix top SQL by gets/exec; remove hard parsing; only then consider more CPU.
 
db file sequential read
  Meaning: single-block reads into the buffer cache (index access, table access by rowid, undo for consistent reads).
  Causes: too many reads from an inefficient plan (index range scan touching many rows, nested loops on large row sources); slow storage; buffer cache too small.
  Confirm: SQL ordered by User I/O Wait Time / Reads; Segments by Physical Reads; avg latency vs baseline; IOStat by Function; Buffer Pool Advisory (estimated read reduction at larger sizes).
  Actions: if latency is normal, reduce the number of reads (SQL/plan/indexing); if latency is high, investigate storage; enlarge the cache only if the advisory shows a large read reduction.
 
db file scattered read
  Meaning: multiblock reads into the buffer cache (full table scan, index fast full scan).
  Causes: missing index or poor plan choosing full scans; small tables scanned repeatedly.
  Confirm: SQL by Reads; Segments by Physical Reads; "table scans (long tables)" in Instance Activity.
  Actions: review plans of the responsible SQL.
 
db file parallel read
  Meaning: batched single-block reads (prefetching, nested loop batching, index rowid batched).
  Same analysis as db file sequential read.
 
direct path read
  Meaning: reads into PGA, bypassing the buffer cache (serial direct reads of large segments, parallel query).
  Causes: full scans of large tables; adaptive serial direct path read.
  Confirm: SQL by Reads; IOStat by Function (Direct Reads); "physical reads direct".
  Actions: question the full scan; check whether frequent scans of the same mid-size table would be better cached.
  Related: enq: KO - fast object checkpoint = segment checkpoint before a direct read; frequent on tables with many dirty buffers.
 
direct path read temp / direct path write temp
  Meaning: work areas (sort, hash join, group by) spilled to TEMP.
  Causes: PGA too small for the workload, or SQL joining or sorting very large row sets.
  Confirm: PGA Aggr Summary, "workarea executions - onepass/multipass", PGA Memory Advisory, ASH TEMP_SPACE_ALLOCATED by SQL_ID (query 8.6).
  Actions: fix the SQL first; raise PGA_AGGREGATE_TARGET if the advisory shows the over-allocation count dropping to zero.
 
log file sync
  Meaning: foreground waits at COMMIT for LGWR to write its redo and post back.
  Components: redo write I/O + LGWR posting/wakeup + CPU scheduling of LGWR and the foreground + Data Guard SYNC transport if configured.
  Causes:
    a) log file sync close to log file parallel write, both high -> redo storage latency.
    b) log file sync much greater than log file parallel write -> CPU starvation/scheduling, too many commits, LGWR post/wait or polling overhead.
    c) Data Guard SYNC -> check "SYNC Remote Write" and network latency to the standby.
  Confirm: user commits/s and redo size per transaction (commit per row = tiny redo/txn); log file parallel write avg and histogram; OS LOAD vs NUM_CPUS; IOStat for LGWR.
  Actions: (a) faster redo storage, separate redo from datafile I/O; (b) batch commits in the app, reduce CPU pressure; (c) review the protection mode and network.
 
log file parallel write (background)
  Meaning: LGWR write I/O time. The pure storage component of log file sync.
 
log file switch (checkpoint incomplete) / log file switch (archiving needed) / log file switch completion
  Meaning: sessions blocked because the next online redo log cannot be reused yet.
  Causes: online redo logs too small or too few; DBWR slow to finish the checkpoint; ARCn slow or the archive destination full.
  Confirm: log switches per hour (query 8.7); "log switches (derived)" in Instance Activity; alert log.
  Actions: bigger and/or more redo log groups (common target: a switch every ~15-20 min at peak); check the archive destination.
 
log buffer space
  Meaning: no free space in the log buffer.
  Causes: LGWR too slow (see log file parallel write) or a burst of redo generation; rarely a log buffer that's actually too small.
 
buffer busy waits
  Meaning: waiting for a buffer that another session holds in an incompatible mode.
  Causes: hot blocks: concurrent DML on the same block, right-hand index growth, segment header or freelist contention (MSSM), undo header.
  Confirm: Segments by Buffer Busy Waits; block class in "Buffer Wait Statistics".
  Actions: depend on block class: data block -> spread inserts (hash partitioning, reverse key on index); undo header -> AUM normally handles it; segment header -> ASSM.
 
read by other session
  Meaning: another session is reading the same block from disk; this one waits for it.
  Analysis: treat like physical I/O on hot segments (same as db file sequential/scattered read).
 
free buffer waits
  Meaning: no free buffers; DBWR cannot write dirty buffers fast enough.
  Causes: slow datafile write I/O; too few DB writers; buffer cache too small for the write rate.
  Confirm: IOStat DBWR write latency; "db file parallel write" (background).
 
latch: cache buffers chains
  Meaning: contention on hash chains of hot buffers; driven by very high logical I/O on the same blocks.
  Causes: SQL with high gets/exec hitting the same blocks (nested loops into a small hot table or index root).
  Confirm: SQL by Gets; Segments by Logical Reads.
  Actions: fix SQL logical I/O. Don't tune the latch itself.
 
enq: TX - row lock contention
  Meaning: waiting for a row locked by another transaction. Application-level locking.
  Causes: concurrent updates of the same rows; long transactions; blockers idle in an open transaction (blocker in "SQL*Net message from client").
  Confirm: Segments by Row Lock Waits; ASH blocker analysis (query 8.4).
  Actions: application design: shorter transactions, consistent lock ordering, avoid hot counter rows.
 
enq: TX - index contention
  Meaning: waits on index block splits.
  Causes: right-hand growing index (sequence/timestamp keys) with concurrent inserts; RAC makes it worse.
  Confirm: buffer busy waits / gc buffer busy on the same index; Segments by Buffer Busy Waits; "leaf node splits".
  Actions: hash-partition the index; reverse key index (hurts range scans); scalable sequences (18c+: SCALE).
 
enq: TX - allocate ITL entry
  Meaning: no free ITL slot in a block.
  Confirm: Segments by ITL Waits.
  Actions: raise INITRANS on the segment (applies to new blocks; rebuild/move for existing ones).
 
enq: TM - contention
  Meaning: table-level lock conflicts.
  Most common cause: unindexed foreign key columns; DML/delete on the parent locks the child table (query 8.8).
  Other causes: explicit LOCK TABLE, parallel/direct-path DML, DDL.
 
enq: SQ - contention / row cache lock (dc_sequences)
  Meaning: sequence cache refills.
  Causes: NOCACHE or a small CACHE under a high NEXTVAL rate; ORDER in RAC.
  Actions: CACHE 1000+ for high-rate sequences, NOORDER in RAC unless ordering is required.
 
enq: HW - contention
  Meaning: high-water mark extension under concurrent inserts.
  Causes: concurrent direct/conventional inserts into a segment, LOB segments (especially BasicFile).
  Actions: larger extents; SecureFiles for LOBs; partitioning.
 
enq: CF - contention
  Meaning: control file enqueue.
  Causes: frequent log switches/checkpoints, NOLOGGING operations updating the control file, RMAN activity.
 
cursor: pin S wait on X / library cache: mutex X / cursor: mutex X / cursor: mutex S / library cache lock / library cache pin
  Meaning: shared pool cursor contention.
  Causes: hard parse storms (literals), high version counts, invalidations (stats gathering, DDL, grants on hot objects), many sessions executing the same cursor while it is rebuilt.
  Confirm: hard parses/s; Time Model parse time elapsed and hard parse elapsed; SQL ordered by Version Count / Parse Calls; "parse count (failures)" (SQL with errors still parses); V$SQL_SHARED_CURSOR for the reasons (query 8.9).
  Actions: bind variables; CURSOR_SHARING=FORCE as a stopgap; fix the version-count root cause; reschedule stats/DDL away from peak.
 
latch: shared pool / row cache lock (other dc_ caches)
  Causes: hard parsing, shared pool churn, dictionary cache misses (Dictionary Cache Stats).
 
resmgr:cpu quantum
  Meaning: session throttled by Resource Manager (consumer group, instance caging via CPU_COUNT, or PDB CPU_COUNT/shares in a CDB).
  Confirm: Instance CPU "%DB time waiting for CPU (Resource Manager)"; RSRC_MGR_CPU_WAIT_TIME in OS Statistics; init.ora CPU_COUNT, RESOURCE_MANAGER_PLAN; PDB-level CPU_COUNT.
  Actions: either the cap is too low for the workload or the workload uses too much CPU (top SQL by CPU).
 
acknowledge over PGA limit
  Meaning: PGA_AGGREGATE_LIMIT pressure (CDB-wide or PDB-level); sessions slowed before ORA-04036.
  Confirm: PGA Aggr Summary, max PGA allocated; ASH PGA_ALLOCATED by SQL_ID (query 8.6).
 
SQL*Net more data to client / SQL*Net more data from client
  Meaning: large payloads; network bandwidth or latency, or a small SDU/array size.
SQL*Net message to client
  Usually tiny; high average = network issue.
SQL*Net break/reset to client
  Errors raised to the client (exceptions in the app). Check application logs.
SQL*Net message from client
  IDLE. Excluded from DB Time. High round-trip counts per execute (SQL*Net roundtrips) indicate a chatty application (row-by-row fetching, small fetch size).
 
Disk file operations I/O
  File open/close/resize overhead; frequent opens (many datafiles, DB_FILES), or slow storage metadata operations.
 
os thread startup
  Spawning processes (PX slaves, dynamic background). Frequent with parallel queries when PARALLEL_MIN_SERVERS is too low.
 
PX Deq Credit: send blkd / PX Deq: Execute Reply / PX Deq: Table Q Normal
  Mostly coordination/idle waits for PX. Real issues: DOP skew, a serial step in a parallel plan, producer-consumer imbalance. Use SQL Monitor.
 
control file sequential read / control file parallel write
  High counts: frequent queries of V$ views backed by the control file (monitoring tools), RMAN, many log switches.
 
Exadata events
  cell single block physical read     ~ db file sequential read (check flash cache hit ratio)
  cell multiblock physical read       ~ db file scattered read
  cell smart table scan / cell smart index scan   offloaded scans (good); high time = large scans, check "cell physical IO bytes eligible for predicate offload" vs "returned by smart scan"
  cell list of blocks physical read   ~ db file parallel read
 
RAC global cache events
  gc cr block 2-way / gc current block 2-way / 3-way
    Normal block shipping. Problem only if latency is high (>~1 ms on modern interconnect) or the volume is excessive.
  gc cr block busy / gc current block busy
    Holder had to do work before shipping, most often a redo flush on the holding instance. Check "gc cr/current block flush time" in Workload Characteristics and log file parallel write on the remote instance.
  gc buffer busy acquire / gc buffer busy release
    Hot block contended across instances (right-hand indexes, ORDER sequences, hot rows). Segments by Global Cache Buffer Busy. Actions: application/service affinity, hash partitioning, NOORDER sequences.
  gc cr block congested / gc current block congested
    LMS could not be scheduled in time -> CPU starvation on the serving node.
  gc cr/current grant 2-way
    Block not in any cache; permission to read from disk. Its cost is mainly the subsequent disk read.
  gc cr multi block request
    Multiblock reads under RAC (full scans).
  gc cr block lost / gc current block lost / "gc blocks lost" statistic
    Interconnect packet loss. Any sustained non-zero value is a problem: check NIC errors, MTU consistency, UDP buffer sizes, network.
  Also check: Interconnect Ping Latency Stats (500B and 8K), Global Cache Load Profile (GCS/GES messages per second), Dynamic Remastering Stats.
 
======================================================================
SECTION 6. LOAD PROFILE AND INSTANCE ACTIVITY INTERPRETATION
======================================================================
- Buffer Hit %: meaningless alone. A low hit ratio without significant I/O waits isn't a problem; a 99.9% hit ratio can hide massive logical I/O.
- Soft Parse % below ~95%: hard parsing. Confirm with hard parses/s and Time Model hard parse elapsed.
- Execute to Parse % low: the app re-parses every execution (no statement caching). Parse Calls ~ Executions in SQL ordered by Parse Calls.
- Parse CPU to Parse Elapsd % low: parsing waits on latches/mutexes (contention, not CPU).
- Hard parses/s: no universal threshold; >~50-100/s together with parse time >~5-10% of DB Time is significant.
- Logons/s sustained above ~1-2/s: no connection pooling (connection storms). Check "connection management call elapsed time" in Time Model. Fix: UCP/DRCP/app pool.
- User commits/s high with small redo size per transaction: commit-per-row pattern; drives log file sync.
- Rollbacks per transaction / user rollbacks: high = application errors or framework auto-rollbacks.
- table fetch continued row: chained or migrated rows (PCTFREE too low, rows grown by updates, >255 columns).
- data blocks consistent reads - undo records applied: long queries reading blocks modified by others; CPU and undo overhead.
- workarea executions - onepass / multipass: any multipass is bad; onepass is acceptable for large sorts.
- SQL*Net roundtrips to/from client per user call or per execute: chattiness.
- parse count (failures): SQL failing at parse (ORA-00942 etc.); can drive mutex contention.
- physical reads direct temporary tablespace: temp spill volume.
- redo size per second: compare with the redo log size to get the switch interval.
 
======================================================================
SECTION 7. CAUSAL PATTERNS (symptom set -> mechanism -> confirmation -> fix)
======================================================================
P1 Commit storm
  Symptoms: log file sync is the top event; log file sync much greater than log file parallel write; high user commits/s; small redo per transaction.
  Mechanism: each commit forces an LGWR post/write/wakeup cycle; the fixed per-commit overhead dominates.
  Confirm: commits/s vs transactions/s; SQL ordered by Executions (single-row DML in loops).
  Fix: batch commits in the application.
 
P2 Slow redo storage
  Symptoms: log file sync and log file parallel write both high and close to each other (> ~2-3 ms on flash).
  Confirm: IOStat by Function LGWR latency; histogram; shared storage with datafiles or backups.
  Fix: faster or dedicated redo storage; check the multiplexing destinations.
 
P3 CPU starvation
  Symptoms: OS LOAD > NUM_CPUS; host busy >~85-90%; log file sync much greater than log file parallel write; gc ... congested; latch/mutex sleeps; every wait inflated.
  Mechanism: runnable processes (including LGWR and LMS) wait in the OS run queue; Oracle counts this as wait time or DB CPU.
  Confirm: DB CPU vs host busy (another consumer if host busy >> DB share); resmgr:cpu quantum if caged.
  Fix: reduce CPU demand (top SQL by CPU/gets), remove other consumers, then add CPU.
 
P4 Hard parse storm
  Symptoms: high hard parses/s, low Soft Parse %, significant parse time, cursor/library cache mutex waits, latch: shared pool.
  Mechanism: literals make every statement unique; each hard parse serialises on shared pool structures.
  Confirm: SQL ordered by Parse Calls / Sharable Memory; similar SQL text that differs only in literals (FORCE_MATCHING_SIGNATURE).
  Fix: bind variables; CURSOR_SHARING=FORCE as a stopgap.
 
P5 High version count
  Symptoms: SQL ordered by Version Count high (hundreds+); cursor: mutex / library cache: mutex X on those SQL_IDs.
  Confirm: V$SQL_SHARED_CURSOR reasons (BIND_MISMATCH, BIND_LENGTH_UPGRADEABLE, OPTIMIZER_MISMATCH, ROLL_INVALID_MISMATCH, ...).
  Fix: depends on the reason (consistent bind types and lengths, session parameter consistency, known bugs/patches).
 
P6 Plan regression
  Symptoms: same SQL_ID, elapsed/exec and gets/exec jumped; often a new plan_hash_value. Compare mode: "different plan" class.
  Confirm: query 8.2 (plan history), DBMS_XPLAN.DISPLAY_AWR for both plans.
  Fix: SQL Plan Baseline to pin the good plan (SPM is included in Enterprise Edition); then fix the cause (stats, binds, histograms).
 
P7 Inefficient SQL logical I/O
  Symptoms: DB CPU dominant; SQL with very high gets/exec relative to rows/exec; latch: cache buffers chains.
  Fix: indexing, plan correction, rewrite. Don't add CPU first.
 
P8 Temp spills
  Symptoms: direct path read/write temp in the top events; onepass/multipass work areas.
  Confirm: query 8.6 (TEMP/PGA by SQL_ID), PGA Memory Advisory.
  Fix: SQL first; then PGA_AGGREGATE_TARGET if the advisory supports it.
 
P9 Row lock contention
  Symptoms: enq: TX - row lock contention; Segments by Row Lock Waits concentrated on a few objects.
  Confirm: query 8.4; blocker idle in "SQL*Net message from client" = open transaction held by the app.
  Fix: application transaction design.
 
P10 Hot right-hand index (insert contention)
  Symptoms: enq: TX - index contention, buffer busy waits on an index, gc buffer busy in RAC, often with enq: SQ.
  Fix: hash-partitioned index, reverse key, scalable sequence, larger sequence CACHE + NOORDER.
 
P11 Undersized redo logs
  Symptoms: log file switch (checkpoint incomplete) or (archiving needed); many switches per hour.
  Fix: bigger/more redo groups; check DBWR and archiver throughput.
 
P12 Connection storm
  Symptoms: high logons/s; connection management call elapsed time significant; CPU spent on process creation.
  Fix: connection pooling (UCP, DRCP, app-side pool); a logon trigger audit can amplify it.
 
P13 Not the database
  Symptoms: AAS far below CPU count; no dominant event; DB Time small relative to Elapsed; many SQL*Net roundtrips.
  Conclusion: response time is spent outside the DB (app CPU, network, client think time, row-by-row fetching). Say so; suggest app-tier tracing, fetch-size tuning or SQL trace of a single session.
 
P14 Noisy neighbour (CDB)
  Symptoms: PDB-level report; host busy or LOAD high while this PDB's DB CPU is modest; resmgr:cpu quantum.
  Fix: CDB resource plan / PDB CPU_COUNT review; investigate the other PDBs.
 
P15 RAC block shipping overhead
  Symptoms: high Cluster wait class; gc buffer busy on few segments; gc current block busy with high flush time.
  Fix: service/data affinity, hash partitioning of hot objects, NOORDER sequences, fix remote redo write latency.
 
======================================================================
SECTION 8. FOLLOW-UP QUERIES
All DBA_HIST and ASH queries need the Diagnostics Pack. SQL Monitor needs the Tuning Pack.
======================================================================
 
8.1 Execution plans of a SQL_ID from AWR
  SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_AWR('&sql_id', NULL, NULL, 'ADVANCED'));
  -- DISPLAY_AWR is deprecated in favour of DISPLAY_WORKLOAD_REPOSITORY, which also covers
  -- remote/imported snapshots. DISPLAY_AWR still works for the local DBID.
 
8.2 Plan and per-execution history of a SQL_ID
  SELECT s.snap_id,
         TO_CHAR(sn.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
         s.instance_number AS inst,
         s.plan_hash_value,
         s.executions_delta AS execs,
         ROUND(s.elapsed_time_delta / NULLIF(s.executions_delta, 0) / 1000, 2) AS ela_ms_per_exec,
         ROUND(s.cpu_time_delta     / NULLIF(s.executions_delta, 0) / 1000, 2) AS cpu_ms_per_exec,
         ROUND(s.buffer_gets_delta  / NULLIF(s.executions_delta, 0))           AS gets_per_exec,
         ROUND(s.disk_reads_delta   / NULLIF(s.executions_delta, 0))           AS reads_per_exec,
         ROUND(s.rows_processed_delta / NULLIF(s.executions_delta, 0))         AS rows_per_exec
  FROM   dba_hist_sqlstat s
  JOIN   dba_hist_snapshot sn
         ON  sn.snap_id = s.snap_id
         AND sn.dbid = s.dbid
         AND sn.instance_number = s.instance_number
  WHERE  s.sql_id = '&sql_id'
  ORDER  BY s.snap_id, s.instance_number;
 
8.3 ASH: top events and SQL in a time window (DBA_HIST samples every 10 s, so COUNT(*) x 10 ~ DB Time in seconds)
  SELECT NVL(event, 'ON CPU') AS event,
         sql_id,
         COUNT(*) * 10 AS est_db_time_s
  FROM   dba_hist_active_sess_history
  WHERE  sample_time BETWEEN TO_TIMESTAMP('&t_from', 'YYYY-MM-DD HH24:MI')
                         AND TO_TIMESTAMP('&t_to',   'YYYY-MM-DD HH24:MI')
  GROUP  BY NVL(event, 'ON CPU'), sql_id
  ORDER  BY est_db_time_s DESC
  FETCH FIRST 20 ROWS ONLY;
  -- For the last ~1 hour use V$ACTIVE_SESSION_HISTORY (1 s samples: COUNT(*) ~ seconds).
 
8.4 ASH: who blocks row lock waits
  SELECT blocking_inst_id, blocking_session, blocking_session_serial#,
         sql_id, current_obj#,
         COUNT(*) * 10 AS wait_s
  FROM   dba_hist_active_sess_history
  WHERE  event = 'enq: TX - row lock contention'
  AND    sample_time BETWEEN TO_TIMESTAMP('&t_from', 'YYYY-MM-DD HH24:MI')
                         AND TO_TIMESTAMP('&t_to',   'YYYY-MM-DD HH24:MI')
  GROUP  BY blocking_inst_id, blocking_session, blocking_session_serial#, sql_id, current_obj#
  ORDER  BY wait_s DESC;
  -- Then check what the blocker was doing in the same window (its own event, sql_id, or idle).
  -- Map current_obj# with DBA_OBJECTS.OBJECT_ID.
 
8.5 Event latency histogram (cumulative since instance startup)
  SELECT event, wait_time_milli, wait_count
  FROM   v$event_histogram
  WHERE  event = '&event_name'
  ORDER  BY wait_time_milli;
  -- For the AWR window, prefer the report's "Wait Event Histogram" section.
 
8.6 ASH: peak TEMP and PGA per SQL_ID (per-session peak)
  SELECT sql_id,
         ROUND(MAX(temp_space_allocated) / 1024 / 1024) AS max_temp_mb,
         ROUND(MAX(pga_allocated)        / 1024 / 1024) AS max_pga_mb
  FROM   dba_hist_active_sess_history
  WHERE  sample_time BETWEEN TO_TIMESTAMP('&t_from', 'YYYY-MM-DD HH24:MI')
                         AND TO_TIMESTAMP('&t_to',   'YYYY-MM-DD HH24:MI')
  GROUP  BY sql_id
  ORDER  BY max_temp_mb DESC NULLS LAST
  FETCH FIRST 10 ROWS ONLY;
 
8.7 Redo log switches per hour (last 24 h)
  SELECT TO_CHAR(first_time, 'YYYY-MM-DD HH24') AS hour, thread#, COUNT(*) AS switches
  FROM   v$log_history
  WHERE  first_time > SYSDATE - 1
  GROUP  BY TO_CHAR(first_time, 'YYYY-MM-DD HH24'), thread#
  ORDER  BY hour, thread#;
  -- Online log sizes:
  SELECT thread#, group#, bytes / 1024 / 1024 AS mb, members, status FROM v$log ORDER BY thread#, group#;
 
8.8 Foreign key columns without a supporting index (approximate; exact for single-column FKs)
  SELECT c.owner, c.table_name, c.constraint_name, cc.column_name, cc.position
  FROM   dba_constraints c
  JOIN   dba_cons_columns cc
         ON cc.owner = c.owner AND cc.constraint_name = c.constraint_name
  WHERE  c.constraint_type = 'R'
  AND    c.owner = UPPER('&owner')
  AND    NOT EXISTS (
           SELECT 1
           FROM   dba_ind_columns ic
           WHERE  ic.table_owner     = cc.owner
           AND    ic.table_name      = cc.table_name
           AND    ic.column_name     = cc.column_name
           AND    ic.column_position = cc.position)
  ORDER  BY c.owner, c.table_name, c.constraint_name, cc.position;
 
8.9 Why a cursor has many child versions
  SELECT * FROM v$sql_shared_cursor WHERE sql_id = '&sql_id';
  -- Look for columns = 'Y' (e.g. BIND_MISMATCH, BIND_LENGTH_UPGRADEABLE, OPTIMIZER_MISMATCH, ROLL_INVALID_MISMATCH).
  -- The REASON column (XML) gives details.
 
8.10 SQL Monitor report (Tuning Pack)
  SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(sql_id => '&sql_id', type => 'TEXT') FROM dual;
 
8.11 Literal-only SQL variants (hard-parse sources) currently in the shared pool
  SELECT force_matching_signature, COUNT(*) AS variants, MIN(sql_id) AS sample_sql_id
  FROM   v$sql
  WHERE  force_matching_signature <> 0
  GROUP  BY force_matching_signature
  HAVING COUNT(*) > 50
  ORDER  BY variants DESC;
 
8.12 Single-instance ASH report for a window
  @?/rdbms/admin/ashrpt.sql   (RAC: ashrpti.sql to choose instances)
 
======================================================================
SECTION 9. THINGS THAT LOOK ALARMING BUT USUALLY AREN'T
======================================================================
- Low Buffer Hit % without significant I/O wait time.
- Idle events: SQL*Net message from client, rdbms ipc message, pmon/smon timer, PX Deq idle events, Streams AQ idle waits, jobq slave wait.
- A large absolute wait count with negligible total time.
- Background events (e.g. db file parallel write) with no matching foreground symptom (free buffer waits, write complete waits).
- "Library Hit %" slightly under 100% with negligible parse time.
- Shared pool advisory suggesting more memory with little estimated time saved.
- High "physical reads" from a nightly batch that's in the window but outside the reported complaint; check the time window first.
 
