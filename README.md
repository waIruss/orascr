-- =============================================================================
-- Connection pooling check from the traditional audit trail (DBA_AUDIT_SESSION)
-- Read-only: creates no objects.
--
-- This database writes TWO audit rows per session:
--   LOGON row  : ACTION_NAME = 'LOGON',  TIMESTAMP = logon time
--   LOGOFF row : ACTION_NAME = 'LOGOFF' or 'LOGOFF BY CLEANUP', written at logoff
-- Both rows share SESSIONID. Each query pairs them (WITH clause "sess"), so
-- session length = logoff time - logon time.
--
--   Correct pooling : few logons, long sessions (close to the pool's max
--                     lifetime, e.g. 20-30 min), flat number of open
--                     sessions per host (= pool size).
--   No pooling      : many logons, sessions of a few seconds or less.
--   Pool churn      : sessions of seconds to minutes; pool grows and shrinks.
--
-- Run in the PDB (the traditional audit trail is per container).
-- Each query reads SYS.AUD$, which usually has no index on time: keep the
-- window short on large audit trails, or run off-peak.
-- =============================================================================

DEFINE days_back = 1
DEFINE app_user  = 'APP_USER'

-- -----------------------------------------------------------------------------
-- 0a. Prerequisites: audit_trail = DB or DB,EXTENDED, and CREATE SESSION audited
-- -----------------------------------------------------------------------------
SELECT name, value FROM v$parameter WHERE name = 'audit_trail';

SELECT user_name, audit_option, success, failure
FROM   dba_stmt_audit_opts
WHERE  audit_option = 'CREATE SESSION';

SELECT MIN(timestamp) AS oldest_record FROM dba_audit_session;

-- -----------------------------------------------------------------------------
-- 0b. Confirm how logoff is recorded: expect a LOGON and a LOGOFF row per SESSIONID
-- -----------------------------------------------------------------------------
SELECT sessionid, instance_number, action_name, timestamp, logoff_time, os_process
FROM   dba_audit_session
WHERE  sessionid IN (SELECT sessionid
                     FROM   dba_audit_session
                     WHERE  timestamp > SYSDATE - 1/24
                     AND    action_name LIKE 'LOGOFF%'
                     FETCH FIRST 5 ROWS ONLY)
ORDER  BY sessionid, timestamp;


-- -----------------------------------------------------------------------------
-- 1. Overview per application user, with a verdict
--    Thresholds are starting points; set them from your pool's max lifetime.
--    Expected logons per host per hour for a correct static pool:
--    pool size x 60 / max lifetime in minutes (e.g. 6 x 60 / 30 = 12).
-- -----------------------------------------------------------------------------
WITH a AS (
  SELECT username, userhost, sessionid, instance_number, action_name, returncode,
         timestamp, logoff_time
  FROM   dba_audit_session
  WHERE  timestamp > SYSDATE - &days_back
  AND    username NOT IN ('SYS', 'SYSTEM', 'DBSNMP', 'SYSMAN')
),
sess AS (
  SELECT l.username, l.userhost, l.timestamp AS logon_time, o.logoff_time,
         NVL(o.cleaned_up, 0) AS cleaned_up,
         CASE WHEN o.logoff_time IS NOT NULL
              THEN (o.logoff_time - l.timestamp) * 86400 END AS dur_s
  FROM   a l
  LEFT   JOIN (SELECT sessionid, instance_number,
                      MAX(COALESCE(logoff_time, timestamp))                              AS logoff_time,
                      MAX(CASE WHEN action_name = 'LOGOFF BY CLEANUP' THEN 1 ELSE 0 END) AS cleaned_up
               FROM   a
               WHERE  action_name LIKE 'LOGOFF%'
               GROUP  BY sessionid, instance_number) o
         ON  o.sessionid = l.sessionid AND o.instance_number = l.instance_number
  WHERE  l.action_name = 'LOGON'
  AND    l.returncode = 0
)
SELECT username, hosts, logons, logons_per_hour, logons_per_host_hour,
       ROUND(median_s) AS median_session_s, pct_under_1min, still_open, cleaned_up,
       CASE
         WHEN completed = 0                         THEN 'NO COMPLETED SESSIONS IN WINDOW'
         WHEN median_s < 10                         THEN 'NO POOLING: new session per request'
         WHEN median_s < 300 OR pct_under_1min > 20 THEN 'POOL CHURN: sessions too short-lived'
         ELSE                                            'POOLED'
       END AS verdict,
       CASE WHEN cleaned_up > 0.05 * logons THEN 'CHECK: sessions not closed cleanly' END AS also_check
FROM  (SELECT username,
              COUNT(DISTINCT userhost)                                          AS hosts,
              COUNT(*)                                                          AS logons,
              ROUND(COUNT(*) / (24 * &days_back), 1)                            AS logons_per_hour,
              ROUND(COUNT(*) / NULLIF(COUNT(DISTINCT userhost), 0)
                             / (24 * &days_back), 1)                            AS logons_per_host_hour,
              COUNT(dur_s)                                                      AS completed,
              PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dur_s)                AS median_s,
              ROUND(100 * SUM(CASE WHEN dur_s < 60 THEN 1 ELSE 0 END)
                        / NULLIF(COUNT(dur_s), 0), 1)                           AS pct_under_1min,
              SUM(CASE WHEN logoff_time IS NULL THEN 1 ELSE 0 END)              AS still_open,
              SUM(cleaned_up)                                                   AS cleaned_up
       FROM   sess
       GROUP  BY username)
ORDER  BY logons DESC;


-- -----------------------------------------------------------------------------
-- 2. One application, per host (pod / server)
--    STILL_OPEN on a live host should equal the pool size.
--    A host with many logons and short sessions = a misbehaving pod
--    (crash loop, health probe connecting, missing pool).
-- -----------------------------------------------------------------------------
WITH a AS (
  SELECT userhost, sessionid, instance_number, action_name, returncode, timestamp, logoff_time
  FROM   dba_audit_session
  WHERE  timestamp > SYSDATE - &days_back
  AND    username = '&app_user'
),
sess AS (
  SELECT l.userhost, l.timestamp AS logon_time, o.logoff_time,
         NVL(o.cleaned_up, 0) AS cleaned_up,
         CASE WHEN o.logoff_time IS NOT NULL
              THEN (o.logoff_time - l.timestamp) * 86400 END AS dur_s
  FROM   a l
  LEFT   JOIN (SELECT sessionid, instance_number,
                      MAX(COALESCE(logoff_time, timestamp))                              AS logoff_time,
                      MAX(CASE WHEN action_name = 'LOGOFF BY CLEANUP' THEN 1 ELSE 0 END) AS cleaned_up
               FROM   a
               WHERE  action_name LIKE 'LOGOFF%'
               GROUP  BY sessionid, instance_number) o
         ON  o.sessionid = l.sessionid AND o.instance_number = l.instance_number
  WHERE  l.action_name = 'LOGON'
  AND    l.returncode = 0
)
SELECT userhost,
       MIN(logon_time)                                           AS first_logon,
       MAX(logon_time)                                           AS last_logon,
       COUNT(*)                                                  AS logons,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dur_s)) AS median_session_s,
       SUM(CASE WHEN logoff_time IS NULL THEN 1 ELSE 0 END)      AS still_open,
       SUM(cleaned_up)                                           AS cleaned_up
FROM   sess
GROUP  BY userhost
ORDER  BY logons DESC;


-- -----------------------------------------------------------------------------
-- 3. One application: how long sessions live
--    Pooled: most sessions in the bucket that contains the pool's max lifetime.
--    Not pooled: most sessions under 10 s.
-- -----------------------------------------------------------------------------
WITH a AS (
  SELECT sessionid, instance_number, action_name, returncode, timestamp, logoff_time
  FROM   dba_audit_session
  WHERE  timestamp > SYSDATE - &days_back
  AND    username = '&app_user'
),
sess AS (
  SELECT (o.logoff_time - l.timestamp) * 86400 AS dur_s
  FROM   a l
  JOIN  (SELECT sessionid, instance_number,
                MAX(COALESCE(logoff_time, timestamp)) AS logoff_time
         FROM   a
         WHERE  action_name LIKE 'LOGOFF%'
         GROUP  BY sessionid, instance_number) o
         ON  o.sessionid = l.sessionid AND o.instance_number = l.instance_number
  WHERE  l.action_name = 'LOGON'
  AND    l.returncode = 0
)
SELECT bucket, COUNT(*) AS sessions
FROM  (SELECT CASE
                WHEN dur_s < 1    THEN '1: < 1 s'
                WHEN dur_s < 10   THEN '2: 1-10 s'
                WHEN dur_s < 60   THEN '3: 10-60 s'
                WHEN dur_s < 600  THEN '4: 1-10 min'
                WHEN dur_s < 3600 THEN '5: 10-60 min'
                ELSE                   '6: > 1 h'
              END AS bucket
       FROM   sess)
GROUP  BY bucket
ORDER  BY bucket;


-- -----------------------------------------------------------------------------
-- 4. One application: open sessions per host, hour by hour
--    Reads 2 extra days so sessions opened before the window are included.
--    Flat at the pool size        = static pool (min = max), as required.
--    Going up and down            = dynamic pool (min < max).
--    Above the agreed pool size   = more than one pool per host, or setting not applied.
-- -----------------------------------------------------------------------------
WITH a AS (
  SELECT userhost, sessionid, instance_number, action_name, returncode, timestamp, logoff_time
  FROM   dba_audit_session
  WHERE  timestamp > SYSDATE - &days_back - 2
  AND    username = '&app_user'
),
sess AS (
  SELECT l.userhost, l.timestamp AS logon_time, o.logoff_time
  FROM   a l
  LEFT   JOIN (SELECT sessionid, instance_number,
                      MAX(COALESCE(logoff_time, timestamp)) AS logoff_time
               FROM   a
               WHERE  action_name LIKE 'LOGOFF%'
               GROUP  BY sessionid, instance_number) o
         ON  o.sessionid = l.sessionid AND o.instance_number = l.instance_number
  WHERE  l.action_name = 'LOGON'
  AND    l.returncode = 0
),
points AS (
  SELECT TRUNC(SYSDATE, 'HH24') - (LEVEL - 1) / 24 AS ts
  FROM   dual
  CONNECT BY LEVEL <= 24 * &days_back
)
SELECT p.ts, s.userhost, COUNT(*) AS open_sessions
FROM   points p
JOIN   sess s
       ON  s.logon_time <= p.ts
       AND (s.logoff_time > p.ts OR s.logoff_time IS NULL)
GROUP  BY p.ts, s.userhost
ORDER  BY s.userhost, p.ts;


-- -----------------------------------------------------------------------------
-- 5. Failed logons by error code (one row per attempt, no pairing needed)
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
