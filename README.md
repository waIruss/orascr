-- =============================================================================
-- Connection pooling check from the traditional audit trail (DBA_AUDIT_SESSION)
--
-- Idea: with AUDIT SESSION, each session is one row. The row is written at
-- logon and updated at logoff (LOGOFF_TIME, ACTION_NAME = 'LOGOFF'), so
-- session duration and logon rate can be read per application and per host.
--
--   Correct pooling : few logons, long sessions (close to the pool's max
--                     lifetime, e.g. 20-30 min), flat number of open
--                     sessions per host (= pool size).
--   No pooling      : many logons, sessions of a few seconds or less.
--   Pool churn      : sessions of seconds to minutes; pool grows and shrinks.
--
-- Run in the PDB (the traditional audit trail is per container).
-- DBA_AUDIT_SESSION reads SYS.AUD$, which usually has no index on time:
-- keep the window short on large audit trails, or run off-peak.
-- =============================================================================
 
DEFINE days_back = 1
DEFINE app_user  = 'APP_USER'
 
-- -----------------------------------------------------------------------------
-- 0. Prerequisites: logons must be audited into the database
--    audit_trail must be DB or DB,EXTENDED (OS/XML write to files instead)
--    and CREATE SESSION must be audited.
-- -----------------------------------------------------------------------------
SELECT name, value FROM v$parameter WHERE name = 'audit_trail';
 
SELECT user_name, audit_option, success, failure
FROM   dba_stmt_audit_opts
WHERE  audit_option = 'CREATE SESSION';
 
-- Oldest record available (the window must be within retention)
SELECT MIN(timestamp) AS oldest_record FROM dba_audit_session;
 
 
-- -----------------------------------------------------------------------------
-- 1. Overview per application user, with a verdict
--    Thresholds are starting points; set them from your pool's max lifetime.
-- -----------------------------------------------------------------------------
WITH s AS (
  SELECT username,
         userhost,
         action_name,
         returncode,
         CASE WHEN returncode = 0 AND logoff_time IS NOT NULL
              THEN (logoff_time - timestamp) * 86400 END AS dur_s
  FROM   dba_audit_session
  WHERE  timestamp > SYSDATE - &days_back
  AND    username NOT IN ('SYS', 'SYSTEM', 'DBSNMP', 'SYSMAN')
),
agg AS (
  SELECT username,
         COUNT(DISTINCT userhost)                                             AS hosts,
         SUM(CASE WHEN returncode = 0 THEN 1 ELSE 0 END)                      AS logons,
         SUM(CASE WHEN returncode <> 0 THEN 1 ELSE 0 END)                     AS failed_logons,
         SUM(CASE WHEN action_name = 'LOGOFF BY CLEANUP' THEN 1 ELSE 0 END)   AS cleaned_up,
         SUM(CASE WHEN action_name = 'LOGON' AND returncode = 0 THEN 1 ELSE 0 END) AS still_open,
         COUNT(dur_s)                                                         AS completed,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dur_s)                   AS median_s,
         SUM(CASE WHEN dur_s < 60 THEN 1 ELSE 0 END)                          AS under_1min
  FROM   s
  GROUP  BY username
)
SELECT username,
       hosts,
       logons,
       ROUND(logons / (24 * &days_back), 1)                          AS logons_per_hour,
       ROUND(logons / NULLIF(hosts, 0) / (24 * &days_back), 1)       AS logons_per_host_hour,
       ROUND(median_s)                                               AS median_session_s,
       ROUND(100 * under_1min / NULLIF(completed, 0), 1)             AS pct_under_1min,
       still_open,
       cleaned_up,
       failed_logons,
       CASE
         WHEN completed = 0                                 THEN 'NO COMPLETED SESSIONS IN WINDOW'
         WHEN median_s < 10                                 THEN 'NO POOLING: new session per request'
         WHEN median_s < 300 OR under_1min > 0.2 * completed THEN 'POOL CHURN: sessions too short-lived'
         ELSE                                                    'POOLED'
       END                                                           AS verdict,
       RTRIM(
         CASE WHEN cleaned_up > 0.05 * logons THEN 'sessions not closed cleanly; ' END ||
         CASE WHEN failed_logons > 0           THEN 'failed logons; '              END,
         '; ')                                                       AS also_check
FROM   agg
ORDER  BY logons DESC;
 
 
-- -----------------------------------------------------------------------------
-- 2. One application, per host (pod / server)
--    STILL_OPEN on a live host should equal the pool size.
--    A host with many logons and short sessions = a misbehaving pod
--    (crash loop, health probe connecting, missing pool).
-- -----------------------------------------------------------------------------
SELECT userhost,
       MIN(timestamp)                                                  AS first_logon,
       MAX(timestamp)                                                  AS last_logon,
       SUM(CASE WHEN returncode = 0 THEN 1 ELSE 0 END)                 AS logons,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY
             CASE WHEN returncode = 0 AND logoff_time IS NOT NULL
                  THEN (logoff_time - timestamp) * 86400 END))         AS median_session_s,
       SUM(CASE WHEN action_name = 'LOGON' AND returncode = 0 THEN 1 ELSE 0 END) AS still_open,
       SUM(CASE WHEN action_name = 'LOGOFF BY CLEANUP' THEN 1 ELSE 0 END) AS cleaned_up,
       SUM(CASE WHEN returncode <> 0 THEN 1 ELSE 0 END)                AS failed_logons
FROM   dba_audit_session
WHERE  timestamp > SYSDATE - &days_back
AND    username = '&app_user'
GROUP  BY userhost
ORDER  BY logons DESC;
 
 
-- -----------------------------------------------------------------------------
-- 3. One application: how long sessions live
--    Pooled: most sessions in the bucket that contains the pool's max lifetime.
--    Not pooled: most sessions under 10 s.
-- -----------------------------------------------------------------------------
SELECT bucket, COUNT(*) AS sessions
FROM  (SELECT CASE
                WHEN d < 1    THEN '1: < 1 s'
                WHEN d < 10   THEN '2: 1-10 s'
                WHEN d < 60   THEN '3: 10-60 s'
                WHEN d < 600  THEN '4: 1-10 min'
                WHEN d < 3600 THEN '5: 10-60 min'
                ELSE               '6: > 1 h'
              END AS bucket
       FROM  (SELECT (logoff_time - timestamp) * 86400 AS d
              FROM   dba_audit_session
              WHERE  timestamp > SYSDATE - &days_back
              AND    username = '&app_user'
              AND    returncode = 0
              AND    logoff_time IS NOT NULL))
GROUP  BY bucket
ORDER  BY bucket;
 
 
-- -----------------------------------------------------------------------------
-- 4. One application: open sessions per host, hour by hour
--    Flat at the pool size        = static pool (min = max), as required.
--    Going up and down            = dynamic pool (min < max).
--    Above the agreed pool size   = more than one pool per host, or setting not applied.
-- -----------------------------------------------------------------------------
WITH points AS (
  SELECT TRUNC(SYSDATE, 'HH24') - (LEVEL - 1) / 24 AS ts
  FROM   dual
  CONNECT BY LEVEL <= 24 * &days_back
),
sess AS (
  SELECT userhost, timestamp AS logon_time, logoff_time
  FROM   dba_audit_session
  WHERE  username = '&app_user'
  AND    returncode = 0
  AND    timestamp > SYSDATE - &days_back - 2      -- sessions opened before the window
  AND    (logoff_time IS NULL OR logoff_time > SYSDATE - &days_back)
)
SELECT p.ts, s.userhost, COUNT(*) AS open_sessions
FROM   points p
JOIN   sess s
       ON  s.logon_time <= p.ts
       AND (s.logoff_time > p.ts OR s.logoff_time IS NULL)
GROUP  BY p.ts, s.userhost
ORDER  BY s.userhost, p.ts;
 
 
-- -----------------------------------------------------------------------------
-- 5. Failed logons by error code
--    1017  = invalid username/password (often a pool retrying with old credentials)
--    18    = maximum number of sessions exceeded (SESSIONS limit reached)
--    28000 = account locked
--    2391  = SESSIONS_PER_USER limit exceeded
-- -----------------------------------------------------------------------------
SELECT username, userhost, returncode, COUNT(*) AS attempts,
       MIN(timestamp) AS first_seen, MAX(timestamp) AS last_seen
FROM   dba_audit_session
WHERE  timestamp > SYSDATE - &days_back
AND    returncode <> 0
GROUP  BY username, userhost, returncode
ORDER  BY attempts DESC;
