#!/usr/bin/env bash
# Adds the 5 'Trends' chart scripts (SQL + description + list entry) to the health-check scripts tree.
# Usage: bash add_trend_scripts.sh [work_dir]     (default: $HOME/healthchecks)
# Data source: AWR per-container views (DBA_HIST_CON_*), queried from the PDB; RAC instances aggregated
# (deltas per instance and startup, then summed per snapshot). Host CPU is per node (whole host).
# Heredocs are quoted (<<'EOF') so bash leaves $database, &awr_days etc. alone.
set -euo pipefail

S="${1:-$HOME/healthchecks}/scripts"
[ -d "$S/sqls" ] && [ -d "$S/descs" ] || { echo "No $S/sqls or $S/descs - wrong work_dir?" >&2; exit 1; }
L="$S/list_of_scripts.txt"
touch "$L"
[ -s "$L" ] && [ -n "$(tail -c1 "$L")" ] && echo >> "$L"      # make sure the list ends with a newline

HEAD=$(cat <<'EOF'
SET ECHO OFF
-- Trends chart data for templates/trends.html.j2. Output, all '|'-separated:
--   CHART|line or stacked|title|v-axis title, then header, then rows (snapshot time first).
-- awr_days is DEFINEd by the role (execute_sqls.yml). Manual run: DEFINE awr_days = 7 first.
SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TRIMOUT ON
EOF
)

SNAP=$(cat <<'EOF'
WITH snap AS (
  SELECT /*+ MATERIALIZE */ snap_id, dbid, instance_number, startup_time,
         CAST(end_interval_time AS DATE) AS end_time,
         (CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE)) * 86400 AS ela_sec
  FROM   dba_hist_snapshot
  WHERE  dbid = (SELECT dbid FROM v$database)
  AND    end_interval_time > SYSDATE - &awr_days
),
EOF
)

add() {   # add <sql_file> <short_desc> <description>   (SQL body on stdin)
  { printf '%s\n' "$HEAD"; cat; } > "$S/sqls/$1.sql"
  printf '%s\n' "$3" > "$S/descs/$1.txt"
  grep -q ",$1\$" "$L" || echo "Trends,$2,$1" >> "$L"
  echo "  $1"
}

echo "Adding to $S:"

# ------------------------------------------------------------------ 1. AAS vs CPU_COUNT
{ cat <<'EOF'
PROMPT CHART|line|Average active sessions: DB time vs DB CPU|Active sessions
PROMPT SNAP_TIME|DB time|DB CPU|CPU_COUNT (current)
EOF
printf '%s\n' "$SNAP"
cat <<'EOF'
tm AS (
  SELECT s.snap_id, s.end_time, s.ela_sec, t.stat_name,
         t.value - LAG(t.value) OVER (PARTITION BY t.instance_number, s.startup_time, t.stat_name
                                      ORDER BY t.snap_id) AS delta
  FROM   dba_hist_con_sys_time_model t
  JOIN   snap s ON s.snap_id = t.snap_id AND s.dbid = t.dbid AND s.instance_number = t.instance_number
  WHERE  t.stat_name IN ('DB time', 'DB CPU')
),
agg AS (
  SELECT snap_id, MAX(end_time) AS end_time, MAX(ela_sec) AS ela_sec,
         SUM(DECODE(stat_name, 'DB time', delta)) AS db_time,
         SUM(DECODE(stat_name, 'DB CPU',  delta)) AS db_cpu
  FROM   tm
  WHERE  delta >= 0
  GROUP  BY snap_id
)
SELECT TO_CHAR(end_time, 'YYYY-MM-DD"T"HH24:MI:SS')
       || '|' || TO_CHAR(db_time / 1e6 / ela_sec, 'FM999990.00')
       || '|' || TO_CHAR(db_cpu  / 1e6 / ela_sec, 'FM999990.00')
       || '|' || (SELECT value FROM v$parameter WHERE name = 'cpu_count')
FROM   agg
WHERE  ela_sec > 0
ORDER  BY snap_id;
EOF
} | add trend_aas "Average active sessions" \
  "Average active sessions of this PDB per AWR snapshot: DB time (all foreground activity) and DB CPU, summed over RAC instances. The dashed line is the current CPU_COUNT of the PDB; DB CPU close to it means the PDB is CPU-bound."

# ------------------------------------------------------------------ 2. AAS by wait class
{ cat <<'EOF'
PROMPT CHART|stacked|Average active sessions by wait class|Active sessions
PROMPT SNAP_TIME|CPU|User I/O|System I/O|Commit|Concurrency|Application|Configuration|Network|Scheduler|Cluster|Administrative|Queueing|Other
EOF
printf '%s\n' "$SNAP"
cat <<'EOF'
ev AS (
  SELECT s.snap_id, s.end_time, s.ela_sec, e.wait_class AS cls,
         e.time_waited_micro - LAG(e.time_waited_micro) OVER (PARTITION BY e.instance_number, s.startup_time, e.event_id
                                                              ORDER BY e.snap_id) AS delta
  FROM   dba_hist_con_system_event e
  JOIN   snap s ON s.snap_id = e.snap_id AND s.dbid = e.dbid AND s.instance_number = e.instance_number
  WHERE  e.wait_class <> 'Idle'
  UNION ALL
  SELECT s.snap_id, s.end_time, s.ela_sec, 'CPU',
         t.value - LAG(t.value) OVER (PARTITION BY t.instance_number, s.startup_time ORDER BY t.snap_id)
  FROM   dba_hist_con_sys_time_model t
  JOIN   snap s ON s.snap_id = t.snap_id AND s.dbid = t.dbid AND s.instance_number = t.instance_number
  WHERE  t.stat_name = 'DB CPU'
),
agg AS (
  SELECT snap_id, MAX(end_time) AS end_time, MAX(ela_sec) AS ela_sec,
         SUM(DECODE(cls, 'CPU',            delta)) AS c_cpu,
         SUM(DECODE(cls, 'User I/O',       delta)) AS c_uio,
         SUM(DECODE(cls, 'System I/O',     delta)) AS c_sio,
         SUM(DECODE(cls, 'Commit',         delta)) AS c_com,
         SUM(DECODE(cls, 'Concurrency',    delta)) AS c_con,
         SUM(DECODE(cls, 'Application',    delta)) AS c_app,
         SUM(DECODE(cls, 'Configuration',  delta)) AS c_cfg,
         SUM(DECODE(cls, 'Network',        delta)) AS c_net,
         SUM(DECODE(cls, 'Scheduler',      delta)) AS c_sch,
         SUM(DECODE(cls, 'Cluster',        delta)) AS c_clu,
         SUM(DECODE(cls, 'Administrative', delta)) AS c_adm,
         SUM(DECODE(cls, 'Queueing',       delta)) AS c_que,
         SUM(DECODE(cls, 'Other',          delta)) AS c_oth
  FROM   ev
  WHERE  delta >= 0
  GROUP  BY snap_id
)
SELECT TO_CHAR(end_time, 'YYYY-MM-DD"T"HH24:MI:SS')
       || '|' || TO_CHAR(NVL(c_cpu, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_uio, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_sio, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_com, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_con, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_app, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_cfg, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_net, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_sch, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_clu, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_adm, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_que, 0) / 1e6 / ela_sec, 'FM999990.000')
       || '|' || TO_CHAR(NVL(c_oth, 0) / 1e6 / ela_sec, 'FM999990.000')
FROM   agg
WHERE  ela_sec > 0
ORDER  BY snap_id;
EOF
} | add trend_wait_class "Active sessions by wait class" \
  "Where the DB time of this PDB goes: CPU plus the non-idle wait classes, as average active sessions. A visible Scheduler band usually means Resource Manager CPU throttling."

# ------------------------------------------------------------------ 3. Host CPU per node
{ cat <<'EOF'
PROMPT CHART|line|Host CPU busy % per node (whole host: all PDBs and databases)|% busy
EOF
printf '%s\n' "$SNAP"
cat <<'EOF'
os AS (
  SELECT s.snap_id, s.end_time, o.instance_number, o.stat_name,
         o.value - LAG(o.value) OVER (PARTITION BY o.instance_number, s.startup_time, o.stat_name
                                      ORDER BY o.snap_id) AS delta
  FROM   dba_hist_osstat o
  JOIN   snap s ON s.snap_id = o.snap_id AND s.dbid = o.dbid AND s.instance_number = o.instance_number
  WHERE  o.stat_name IN ('BUSY_TIME', 'IDLE_TIME')
),
busy AS (
  SELECT snap_id, instance_number, MAX(end_time) AS end_time,
         100 * SUM(DECODE(stat_name, 'BUSY_TIME', delta)) / NULLIF(SUM(delta), 0) AS pct
  FROM   os
  WHERE  delta >= 0
  GROUP  BY snap_id, instance_number
),
inst  AS (SELECT DISTINCT instance_number FROM busy),
times AS (SELECT snap_id, MAX(end_time) AS end_time FROM busy GROUP BY snap_id)
SELECT txt FROM (
  SELECT 0 AS ord, 0 AS snap_id,
         'SNAP_TIME|' || LISTAGG('Node ' || instance_number, '|') WITHIN GROUP (ORDER BY instance_number) AS txt
  FROM   inst
  UNION ALL
  SELECT 1, t.snap_id,
         TO_CHAR(t.end_time, 'YYYY-MM-DD"T"HH24:MI:SS') || '|'
         || LISTAGG(NVL(TO_CHAR(b.pct, 'FM990.0'), '-'), '|') WITHIN GROUP (ORDER BY i.instance_number)
  FROM   times t
  CROSS  JOIN inst i
  LEFT   JOIN busy b ON b.snap_id = t.snap_id AND b.instance_number = i.instance_number
  GROUP  BY t.snap_id, t.end_time
)
ORDER  BY ord, snap_id;
EOF
} | add trend_host_cpu "Host CPU busy per node" \
  "Host CPU busy percent per RAC node from OS statistics. It covers the whole host, all PDBs and databases on it, so a high value while this PDB is quiet points to its neighbours."

# ------------------------------------------------------------------ 4. Wait latency
{ cat <<'EOF'
PROMPT CHART|line|Average wait latency|ms per wait
PROMPT SNAP_TIME|db file sequential read|direct path read|log file sync
EOF
printf '%s\n' "$SNAP"
cat <<'EOF'
ev AS (
  SELECT s.snap_id, s.end_time, e.event_name,
         e.time_waited_micro - LAG(e.time_waited_micro) OVER (PARTITION BY e.instance_number, s.startup_time, e.event_id
                                                              ORDER BY e.snap_id) AS d_time,
         e.total_waits       - LAG(e.total_waits)       OVER (PARTITION BY e.instance_number, s.startup_time, e.event_id
                                                              ORDER BY e.snap_id) AS d_waits
  FROM   dba_hist_con_system_event e
  JOIN   snap s ON s.snap_id = e.snap_id AND s.dbid = e.dbid AND s.instance_number = e.instance_number
  WHERE  e.event_name IN ('db file sequential read', 'direct path read', 'log file sync')
),
agg AS (
  SELECT snap_id, MAX(end_time) AS end_time,
         SUM(DECODE(event_name, 'db file sequential read', d_time))  AS t1,
         SUM(DECODE(event_name, 'db file sequential read', d_waits)) AS w1,
         SUM(DECODE(event_name, 'direct path read',        d_time))  AS t2,
         SUM(DECODE(event_name, 'direct path read',        d_waits)) AS w2,
         SUM(DECODE(event_name, 'log file sync',           d_time))  AS t3,
         SUM(DECODE(event_name, 'log file sync',           d_waits)) AS w3
  FROM   ev
  WHERE  d_time >= 0 AND d_waits >= 0
  GROUP  BY snap_id
)
SELECT TO_CHAR(end_time, 'YYYY-MM-DD"T"HH24:MI:SS')
       || '|' || TO_CHAR(t1 / NULLIF(w1, 0) / 1000, 'FM999990.00')
       || '|' || TO_CHAR(t2 / NULLIF(w2, 0) / 1000, 'FM999990.00')
       || '|' || TO_CHAR(t3 / NULLIF(w3, 0) / 1000, 'FM999990.00')
FROM   agg
ORDER  BY snap_id;
EOF
} | add trend_latency "Wait latency" \
  "Average time per wait for single-block reads, direct path reads and commits (log file sync), per AWR snapshot. Gaps mean there were no waits of that kind in the interval."

# ------------------------------------------------------------------ 5. PDB I/O throughput
{ cat <<'EOF'
PROMPT CHART|line|PDB I/O throughput|MB/s
PROMPT SNAP_TIME|Physical read|Physical write|Redo generated
EOF
printf '%s\n' "$SNAP"
cat <<'EOF'
st AS (
  SELECT s.snap_id, s.end_time, s.ela_sec, t.stat_name,
         t.value - LAG(t.value) OVER (PARTITION BY t.instance_number, s.startup_time, t.stat_name
                                      ORDER BY t.snap_id) AS delta
  FROM   dba_hist_con_sysstat t
  JOIN   snap s ON s.snap_id = t.snap_id AND s.dbid = t.dbid AND s.instance_number = t.instance_number
  WHERE  t.stat_name IN ('physical read total bytes', 'physical write total bytes', 'redo size')
),
agg AS (
  SELECT snap_id, MAX(end_time) AS end_time, MAX(ela_sec) AS ela_sec,
         SUM(DECODE(stat_name, 'physical read total bytes',  delta)) AS rd,
         SUM(DECODE(stat_name, 'physical write total bytes', delta)) AS wr,
         SUM(DECODE(stat_name, 'redo size',                  delta)) AS redo
  FROM   st
  WHERE  delta >= 0
  GROUP  BY snap_id
)
SELECT TO_CHAR(end_time, 'YYYY-MM-DD"T"HH24:MI:SS')
       || '|' || TO_CHAR(rd   / 1048576 / ela_sec, 'FM9999990.00')
       || '|' || TO_CHAR(wr   / 1048576 / ela_sec, 'FM9999990.00')
       || '|' || TO_CHAR(redo / 1048576 / ela_sec, 'FM9999990.00')
FROM   agg
WHERE  ela_sec > 0
ORDER  BY snap_id;
EOF
} | add trend_io "PDB I/O throughput" \
  "Physical read and write throughput and redo generated by this PDB, in MB/s per AWR snapshot, summed over RAC instances."

echo "List now contains:"
grep -n '^Trends,' "$L"
