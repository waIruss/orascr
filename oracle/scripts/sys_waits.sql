set linesize 200
col username format a10
col event format a30
col machine format a10
col program format a20
col schemaname format a10

PROMPT =====================================
PROMPT Sesje czekajace > 10s z session_wait
PROMPT =====================================
SELECT a.SID, a.serial#, a.username, a.command, a.schemaname, a.osuser,
       a.process, a.machine, a.terminal, a.program, b.wait_time, b.event
  FROM v$session a,
       (SELECT   SID, event, SUM (wait_time) AS wait_time
            FROM v$session_wait
           WHERE event NOT IN
                    ('dispatcher timer','lock element cleanup','Null event','parallel query dequeue wait','parallel query idle wait - Slaves',
                     'pipe get','PL/SQL lock timer','pmon timer','rdbms ipc message','slave wait','smon timer','SQL*Net break/reset to client',
                     'SQL*Net message from client','SQL*Net message to client','SQL*Net more data to client',
                     'virtual circuit status','jobq slave wait','wakeup time manager'
                    )
        GROUP BY SID, event
          HAVING SUM (wait_time) > 10) b
 WHERE a.SID = b.SID;

PROMPT =====================================
PROMPT Current waits
PROMPT =====================================
col seconds_in_wait format 999999
col sql_id format a15

SELECT   s.SID, s.serial#, w.event, w.seconds_in_wait, s.machine, s.program,
         schemaname, s.sql_id
    FROM v$session_wait w, v$session s
   WHERE w.event NOT IN
            ('dispatcher timer', 'lock element cleanup', 'Null event',
             'parallel query dequeue wait',
             'parallel query idle wait - Slaves', 'pipe get',
             'PL/SQL lock timer', 'pmon timer', 'rdbms ipc message',
             'slave wait', 'smon timer', 'SQL*Net break/reset to client',
             'SQL*Net message from client', 'SQL*Net message to client',
             'SQL*Net more data to client', 'virtual circuit status',
             'jobq slave wait', 'wakeup time manager')
     AND w.SID = s.SID
    -- AND w.SID = xxx
ORDER BY w.seconds_in_wait DESC;

PROMPT =====================================
PROMPT Grouped waits
PROMPT =====================================

SELECT   COUNT (*) AS session_count, event, SUM (seconds_in_wait)
    FROM v$session_wait
GROUP BY event
ORDER BY session_count DESC;

PROMPT =====================================
PROMPT System-wide Wait Analysis for current wait events
PROMPT =====================================
column c1 heading 'Event|Name'             format a40
column c2 heading 'Total|Waits'            format 999999,999,999
column c3 heading 'Seconds|Waiting'        format 999999,999
column c4 heading 'Total|Timeouts'         format 999999,999,999
column c5 heading 'Average|Wait|(in secs)' format 999999.999


select * from (
select
   event                         c1,
   total_waits                   c2,
   time_waited / 100             c3,
   total_timeouts                c4,
   average_wait    /100          c5
from
   sys.v_$system_event
where
   event not in (
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
    'WMON goes to sleep'
   )
AND event not like 'DFS%'
and   event not like '%done%'
and   event not like '%Idle%'
AND
 event not like 'KXFX%'
order by   c2 desc)
where rownum <20
;


