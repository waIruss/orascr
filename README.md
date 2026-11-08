#!/usr/bin/env bash
# Creates a sample scripts/ tree for ansible-role-db-healthcheck.
# Usage: bash create_sample_scripts.sh [work_dir]     (default: $HOME/healthchecks)
# Heredocs are quoted (<<'EOF') so bash does not expand $database, $instance, ...
set -euo pipefail

S="${1:-$HOME/healthchecks}/scripts"
mkdir -p "$S/sqls" "$S/descs"
[ -f "$S/list_of_scripts.txt" ] && cp "$S/list_of_scripts.txt" "$S/list_of_scripts.txt.bak"

# ---------------------------------------------------------------- list
cat > "$S/list_of_scripts.txt" <<'EOF'
SystemOverview,Database overview,db_overview
InstanceInfo,Instance details,instance_info
Storage,Tablespace usage,tbs_usage
Objects,Invalid objects,invalid_objects
Sessions,Blocking sessions,blocking_sessions
Selftest,Deliberate error (remove after testing),selftest_error
EOF

# ---------------------------------------------------------------- format includes
cat > "$S/set_format.sql" <<'EOF'
-- Included before every script.
SET LINESIZE 250
SET PAGESIZE 1000
SET TRIMOUT ON
SET TRIMSPOOL ON
SET TAB OFF
SET VERIFY OFF
SET HEADING ON
EOF

cat > "$S/set_format_noheading.sql" <<'EOF'
-- Included after set_format.sql for SystemOverview / InstanceInfo only.
-- Those scripts print their own '|'-separated header row, so SQL*Plus headings and paging are off.
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
EOF

# ---------------------------------------------------------------- SystemOverview
cat > "$S/sqls/db_overview.sql" <<'EOF'
-- SystemOverview: rendered as a table by report.html.j2. Output contract:
--   line 1 = title (skipped), line 2 = '|'-separated header, lines 3+ = '|'-separated rows.
--   STATUS column (OK/ERRORS/FAILED/TIMEOUT) drives row colouring; keep it last, never first.
PROMPT Database overview
SELECT txt FROM (
  SELECT 0 AS ord, 'CON_NAME|DB_NAME|DB_ROLE|OPEN_MODE|LOG_MODE|FORCE_LOGGING|FLASHBACK|STATUS' AS txt FROM dual
  UNION ALL
  SELECT 1, SYS_CONTEXT('USERENV','CON_NAME') || '|' || d.name || '|' || d.database_role || '|' ||
            d.open_mode || '|' || d.log_mode || '|' || d.force_logging || '|' || d.flashback_on || '|' ||
            CASE WHEN d.log_mode = 'ARCHIVELOG' THEN 'OK' ELSE 'ERRORS' END
  FROM v$database d
)
ORDER BY ord;
EOF

cat > "$S/descs/db_overview.txt" <<'EOF'
Identity, role and logging configuration of the database. STATUS is ERRORS when the database is not in ARCHIVELOG mode.
EOF

# ---------------------------------------------------------------- InstanceInfo
cat > "$S/sqls/instance_info.sql" <<'EOF'
-- InstanceInfo: same output contract as db_overview.sql.
PROMPT Instance details
SELECT txt FROM (
  SELECT 0 AS ord, 'INST_ID|INSTANCE|HOST|VERSION|STARTED|UPTIME_DAYS|INST_STATUS|STATUS' AS txt FROM dual
  UNION ALL
  SELECT 1 + inst_id, inst_id || '|' || instance_name || '|' || host_name || '|' || version_full || '|' ||
            TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI') || '|' ||
            TO_CHAR(SYSDATE - startup_time, 'FM99990.0') || '|' || status || '|' ||
            CASE WHEN status = 'OPEN' THEN 'OK' ELSE 'ERRORS' END
  FROM gv$instance
)
ORDER BY ord;
EOF

cat > "$S/descs/instance_info.txt" <<'EOF'
Instances serving the database: host, version and uptime. STATUS is ERRORS when an instance is not OPEN.
EOF

# ---------------------------------------------------------------- Storage
cat > "$S/sqls/tbs_usage.sql" <<'EOF'
COLUMN tablespace_name FORMAT a30 HEADING 'TABLESPACE'
COLUMN used_mb  FORMAT 999,999,990
COLUMN max_mb   FORMAT 999,999,990
COLUMN used_pct FORMAT 990.0
COLUMN state    FORMAT a8
SELECT m.tablespace_name,
       ROUND(m.used_space      * t.block_size / 1048576) AS used_mb,
       ROUND(m.tablespace_size * t.block_size / 1048576) AS max_mb,
       m.used_percent AS used_pct,
       CASE WHEN m.used_percent >= 90 THEN 'CRITICAL'
            WHEN m.used_percent >= 80 THEN 'WARNING'
            ELSE 'OK' END AS state
FROM   dba_tablespace_usage_metrics m
JOIN   dba_tablespaces t ON t.tablespace_name = m.tablespace_name
ORDER  BY m.used_percent DESC;
EOF

cat > "$S/descs/tbs_usage.txt" <<'EOF'
Space used per tablespace against its maximum size, autoextend included. WARNING from 80 percent, CRITICAL from 90 percent.
EOF

# ---------------------------------------------------------------- Objects
cat > "$S/sqls/invalid_objects.sql" <<'EOF'
COLUMN owner       FORMAT a30
COLUMN object_type FORMAT a25
SELECT owner, object_type, COUNT(*) AS invalid_count
FROM   dba_objects
WHERE  status = 'INVALID'
GROUP  BY owner, object_type
ORDER  BY owner, object_type;
EOF

cat > "$S/descs/invalid_objects.txt" <<'EOF'
Invalid objects per owner and type. Expected result: no rows.
EOF

# ---------------------------------------------------------------- Sessions
cat > "$S/sqls/blocking_sessions.sql" <<'EOF'
COLUMN blocker  FORMAT a10
COLUMN waiter   FORMAT a10
COLUMN username FORMAT a20
COLUMN event    FORMAT a40
SELECT s.blocking_instance || ',' || s.blocking_session AS blocker,
       s.inst_id || ',' || s.sid AS waiter,
       s.username,
       s.event,
       ROUND(s.wait_time_micro / 1e6) AS wait_s
FROM   gv$session s
WHERE  s.blocking_session IS NOT NULL
ORDER  BY wait_s DESC;
EOF

cat > "$S/descs/blocking_sessions.txt" <<'EOF'
Sessions currently blocked by another session. Expected result: no rows.
EOF

# ---------------------------------------------------------------- Selftest
cat > "$S/sqls/selftest_error.sql" <<'EOF'
-- Deliberately fails to verify the ERRORS path (ORA- line right after "ERROR at line N:").
-- Remove its line from list_of_scripts.txt once the report looks right.
SELECT * FROM healthcheck_selftest_missing_table;
EOF

cat > "$S/descs/selftest_error.txt" <<'EOF'
Deliberate failure that checks the ERRORS classification. Remove after testing.
EOF

echo "Created in $S:"
find "$S" -type f | sort
