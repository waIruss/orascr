prompt =================================================
prompt Specific session waits from v$session_event and v$sesstat
prompt =================================================
set verify off

SELECT   e.event, e.time_waited
    FROM SYS.v_$session_event e
   WHERE e.SID = &&sid
UNION ALL
SELECT   n.NAME, s.VALUE
    FROM SYS.v_$statname n, SYS.v_$sesstat s
   WHERE s.SID = &&sid
     AND n.statistic# = s.statistic#
     AND n.NAME = 'CPU used by this session'
ORDER BY 2 DESC;

set verify on

prompt =================================================
prompt Session waits with SQLs
prompt =================================================

SELECT ss.sid, ss.SERIAL# as serial , sa.HASH_VALUE , executions,cpu_time, round ( cpu_time/decode ( executions,0,1,executions) ) as cpu_per_exec ,sw.event,sw.seconds_in_wait , ss.machine , ss.program , ss.schemaname, sa.SQL_TEXT 
FROM v$session ss , v$sqlarea sa ,  v$session_wait sw 
WHERE ss.SQL_HASH_VALUE = sa.HASH_VALUE
  AND sw.sid = ss.sid
  AND sw.event NOT IN
(
'dispatcher timer',
'lock element cleanup',
'Null event',
'parallel query dequeue wait',
'parallel query idle wait - Slaves',
'pipe get',
'PL/SQL lock timer',
'pmon timer',
'rdbms ipc message',
'slave wait',
'smon timer',
'SQL*Net break/reset to client',
'SQL*Net message from client',
'SQL*Net message to client',
'SQL*Net more data to client',
'virtual circuit status',
'jobq slave wait',
'wakeup time manager')
order by cpu_per_exec desc;