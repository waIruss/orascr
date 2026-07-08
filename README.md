## DB load
set linesize 300
col parsing_schema_name format a10
col SQL_PLAN_BASELINE format a10
col SQL_TEXT format a40
set pagesize 9999
Set wrap off

select ts.sql_id, ts.CPUpct PCT, ts.wt, sa.executions, trunc(sa.disk_reads/decode(sa.executions,0,1,sa.executions)) disk_reads_per_exec, sa.disk_reads,
trunc(sa.buffer_gets/decode(sa.executions,0,1,sa.executions)) buff_get_per_exec, sa.buffer_gets,
trunc(sa.rows_processed/decode(sa.executions,0,1,sa.executions)) rows_per_exec, 
trunc(sa.elapsed_time/1000/decode(sa.executions,0,1,sa.executions)) ms_per_exec,
round(sa.user_io_wait_time/decode(sa.disk_reads,0,1,sa.disk_reads)/1000,2) Single_IO_time_ms,
--sa.outline_category, 
sa.parsing_schema_name, 
sa.sql_plan_baseline, 
sa.sql_text 
from (
select sql_id,  round(count(*)/sum(count(*)) over (), 2) * 100 CPUpct, sum(wait_time) wt   
from v$active_session_history
where sample_time > sysdate - 5/24/60
and sql_id is not null
group by sql_id
order by 2 desc) ts, v$sqlarea sa
where ts.sql_id = sa.sql_id
--and sa.parsing_schema_name = 'MAO_BASE' 
and rownum < 31;

## Detailed SQL stats
Set linesize 300
Set pagesize 80
select to_char(sn.begin_interval_time,'MM-DD HH24:Mi') begin_time, to_char(sn.end_interval_time,'MM-DD HH24:Mi') end_time
, executions_delta Execs
, fetches_delta Fetches
, PLAN_HASH_VALUE PHV
, round((elapsed_time_delta / nvl(nullif(executions_delta,0),1))/1000000,4) ela_per_exec
, round((iowait_delta / nvl(nullif(executions_delta,0),1))/1000000,2) io_per_exec
, round((cpu_time_delta / nvl(nullif(executions_delta,0),1))/1000000,2) cpu_per_exec
, round((apwait_delta / nvl(nullif(executions_delta,0),1))/1000000,8) app_per_exec
, round((ccwait_delta / nvl(nullif(executions_delta,0),1))/1000000,8) cc_per_exec
, round(buffer_gets_delta / nvl(nullif(executions_delta,0),1),2) gets_per_exec
, round(rows_processed_delta / nvl(nullif(executions_delta,0),1),8) rows_per_exec
, round((elapsed_time_delta / nvl(nullif(rows_processed_delta,0),1))/1000000,8) ela_per_row
, round((iowait_delta / nvl(nullif(rows_processed_delta,0),1))/1000000,2) io_per_row
, round(disk_reads_delta / nvl(nullif(rows_processed_delta,0),1),2) read_per_row
, round((iowait_delta / nvl(nullif(disk_reads_delta,0),1))/1000000,8) read_speed
--, s.*
from   dba_hist_sqlstat s
      ,dba_hist_snapshot sn
where  sn.dbid            (+) = s.dbid
  and  sn.instance_number (+) = s.instance_number
  and  sn.snap_id         (+) = s.snap_id
  and  s.sql_id in (
'a2cg78ckbx75n'
)
order by sn.end_interval_time asc, s.snap_id desc, s.sql_id
; 

## find sql_id
select * from dba_hist_sqltext
where lower(sql_text) like lower('%select * from ( select rater%');

##  stats / hash_plan_value
set lines 200
col execs for 999,999,999
col "avg_etime[s]" for 999,999.999999
col avg_lio for 999,999,999.9
col begin_interval_time for a30
col node for 99999
break on plan_hash_value on startup_time skip 1
select ss.snap_id, ss.instance_number node, begin_interval_time, sql_id,  plan_hash_value, rows_processed_delta,
nvl(executions_delta,0) execs,
round((elapsed_time_delta/decode(nvl(executions_delta,0),0,1,executions_delta))/1000000,5) "avg_etime[s]",
round((buffer_gets_delta/decode(nvl(buffer_gets_delta,0),0,1,executions_delta)),2) avg_lio
from DBA_HIST_SQLSTAT S, DBA_HIST_SNAPSHOT SS
where sql_id in ('a2cg78ckbx75n')
and ss.snap_id = S.snap_id
and ss.instance_number = S.instance_number
and executions_delta > 0
order by 3 asc, 1;

## CURRENT sql stats
set verify off feedback off
set serveroutput on
set linesize 250 pagesize 800 long 100000
col owner form A10
col is_bind_sensitive form A6 heading "Bind|sensi"
col is_bind_aware form A6 heading "Bind|aware"
col is_shareable form A6 heading "Is|sharea"
col sql_profile form A25 heading "SQL|Profile"
col sql_patch form A25 heading "SQL|Patch"
col sql_plan_baseline  form A35 heading "SQL Plan|Baseline"
col is_rolling_invalid form A6 heading "roll|inval"
col first_load_time form A14 heading "First|load time"
col last_active_time form A14 heading "Last|active time"

Select
   --s.sql_id, s.force_matching_signature fms,s.sql_text,
   s.child_number child#, s.parsing_schema_name owner, s.plan_hash_value plan_hash,
   --s.fetches,
   s.executions "execs",
   --s.parse_calls, s.loads, s.buffer_gets,
   round(s.buffer_gets/decode(s.executions,0,1,s.executions),2) AS "gets/exec",
   round(s.concurrency_wait_time/1000000,2) "Concur(s)",
   round(s.cpu_time/1000000,2) AS "CPU(s)",
   round(s.elapsed_time/1000000,2) AS "Ela(s)",
   round(s.elapsed_time/1000000/decode(s.executions,0,1,s.executions),4) AS "Ela/exec(s)",
   round(s.user_io_wait_time/1000000,2) AS "IO wait(s)",
   round(s.physical_read_bytes/1024/1024,2) "PhysReadMB",
   --s.OPTIMIZER_COST,
   s.rows_processed AS "rows total",
   round(s.rows_processed/decode(s.executions,0,1,s.executions),2) "rows/exec",
   round(s.buffer_gets/decode(s.rows_processed,0,1,s.rows_processed),2) "gets/row"
from v$sql s
where sql_id='7rpu0kq0rvb38'
order by child_number;

select
  s.child_number child#
  --,loaded_versions,open_versions,fetches,end_of_fetch_count,loads
  ,substr(first_load_time,6,15) first_load_time
  --,invalidations,parse_calls
  --,substr(last_load_time,6,15) last_load_time
  ,to_char(last_active_time, 'MM/DD HH24:MI:SS') last_active_time
  --,is_obsolete
  ,is_bind_sensitive
  ,is_bind_aware
  ,is_shareable
  ,sql_profile
  ,sql_patch
  ,sql_plan_baseline
  ,is_rolling_invalid
from v$sql s
where sql_id='f9sxr33ynk2uf'
order by child_number;

                 

-- statystyki czasowe zapytania (czas wykonania)
  SELECT   TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD HH24'),
           median ( (elapsed_time_delta / (EXECUTIONS_DELTA))/1000000)
              "time_per_exec[s]"
    FROM   DBA_HIST_SQLSTAT a, DBA_HIST_SNAPSHOT b
   WHERE   a.snap_id = b.snap_id AND a.sql_id = 'cxxrhfnyzabb5'
   and A.EXECUTIONS_DELTA >0
GROUP BY   TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD HH24')
ORDER BY   1 desc;


-- history of some stats
  SELECT   ROUND (AVG (a.VALUE)), TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD')
    FROM   DBA_HIST_SYSSTAT a, dba_hist_snapshot b
   WHERE       a.stat_name = 'redo write time'
           AND a.snap_id > 92306
           AND a.snap_id = b.snap_id
GROUP BY   TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD')
ORDER BY   2 DESC;

-- history of db_user
SELECT   *
    FROM dba_hist_active_sess_history
   WHERE user_id = 269
     AND blocking_session_status = 'VALID'
     AND sample_time BETWEEN TO_DATE ('2008-08-05 18:42:00',
                                      'YYYY-MM-DD HH24:mi:ss'
                                     )
                         AND to_date('2008-08-05 18:59:00', 'YYYY-MM-DD HH24:mi:ss')
ORDER BY sample_time DESC;

-- #### DBA_HIST_OSSTAT #### ---
average_IO_wait_time

--dokladnie
  SELECT a.snap_id, a.VALUE, to_char(b.begin_interval_time, 'YYYY-MM-DD')
    FROM (SELECT a.snap_id snap_id, (a.VALUE - b.VALUE) VALUE
            FROM DBA_HIST_OSSTAT a, DBA_HIST_OSSTAT b
           WHERE     a.snap_id = b.snap_id + 1
                 AND a.stat_name = 'IOWAIT_TIME'
                 AND b.stat_name = 'IOWAIT_TIME') a,
         DBA_HIST_SNAPSHOT b
   WHERE a.snap_id = b.snap_id
ORDER BY 1 DESC;

--average daily
  SELECT TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD'),round( AVG (a.VALUE), 2)
    FROM (SELECT a.snap_id snap_id, (a.VALUE - b.VALUE) VALUE
            FROM DBA_HIST_OSSTAT a, DBA_HIST_OSSTAT b
           WHERE     a.snap_id = b.snap_id + 1
                 AND a.stat_name = 'IOWAIT_TIME'
                 AND b.stat_name = 'IOWAIT_TIME') a,
         DBA_HIST_SNAPSHOT b
   WHERE a.snap_id = b.snap_id
GROUP BY TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD')
ORDER BY 1 asc;


-------------------------------------------------------------------------------------------
------------------ ##### DBA_HIST_SYSTEM_EVENT ##### -----------------
-------------------------------------------------------------------------------------------
/*
log file sync
db file sequential read
db file scattered read

select distinct event_name from DBA_HIST_SYSTEM_EVENT
*/

--dokaldnie z podzia³em na instancje
  SELECT TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD HH24:mi'), a.waits, a.time
    FROM (SELECT c.snap_id snap_id,
                 (c.total_waits - d.total_waits) waits,
                 (c.time_waited_micro - d.time_waited_micro) time
            FROM DBA_HIST_SYSTEM_EVENT c, DBA_HIST_SYSTEM_EVENT d
           WHERE     c.snap_id = d.snap_id + 1
                 AND c.event_name = '&&stat_name'
                 AND d.event_name = '&&stat_name'
                 and c.instance_number=&&instance_number
                 and d.instance_number=&&instance_number) a,
         DBA_HIST_SNAPSHOT b
   WHERE a.snap_id = b.snap_id
   and b.instance_number = &&instance_number
   ORDER BY 1 DESC;
   
--dokaldnie sumarycznie dla wszystkich instancji
  SELECT TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD HH24:mi'), a.waits, a.time
    FROM (SELECT c.snap_id snap_id,
                 (sum(c.total_waits) - sum(d.total_waits)) waits,
                 (sum(c.time_waited_micro) - sum(d.time_waited_micro)) time
            FROM DBA_HIST_SYSTEM_EVENT c, DBA_HIST_SYSTEM_EVENT d
           WHERE     c.snap_id = d.snap_id + 1
                 AND c.event_name = '&&stat_name'
                 AND d.event_name = '&&stat_name'
                 group by c.snap_id
                 ) a,
         DBA_HIST_SNAPSHOT b
   WHERE a.snap_id = b.snap_id
   ORDER BY 1 DESC;

--average dla poszczegolnych instancji
  SELECT TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD HH24:Mi'),
         ROUND (AVG (a.time / DECODE (a.waits, 0, 1, a.waits) / 1000), 2)
    FROM (SELECT c.snap_id snap_id,
                 (c.total_waits - d.total_waits) waits,
                 (c.time_waited_micro - d.time_waited_micro) time
            FROM DBA_HIST_SYSTEM_EVENT c, DBA_HIST_SYSTEM_EVENT d
           WHERE     c.snap_id = d.snap_id + 1
                 AND c.event_name = '&&stat_name'
                 AND d.event_name = '&&stat_name'
                 AND c.instance_number = &&instance_number
                 AND d.instance_number = &&instance_number) a,
         DBA_HIST_SNAPSHOT b
   WHERE a.snap_id = b.snap_id AND b.instance_number = &&instance_number
GROUP BY TO_CHAR (b.begin_interval_time,  'YYYY-MM-DD HH24:Mi')
ORDER BY 1 ASC;

--average sumaryczny
  SELECT TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD HH24:mi'),
         ROUND (avg (a.time / DECODE (a.waits, 0, 1, a.waits) / 1000), 2)
    FROM (  SELECT c.snap_id snap_id,
                   (SUM (c.total_waits) - SUM (d.total_waits)) waits,
                   (SUM (c.time_waited_micro) - SUM (d.time_waited_micro)) time
              FROM DBA_HIST_SYSTEM_EVENT c, DBA_HIST_SYSTEM_EVENT d
             WHERE     c.snap_id = d.snap_id + 1
                   AND c.event_name = '&&stat_name'
                   AND d.event_name = '&&stat_name'
          GROUP BY c.snap_id) a,
         DBA_HIST_SNAPSHOT b
   WHERE a.snap_id = b.snap_id
GROUP BY TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD HH24:mi')
ORDER BY 1 ASC;


select snap_id,s.end_interval_time,ev.event_name
,ev.total_waits-lag(ev.total_waits) over (order by snap_id)
,round(ev.time_waited_micro-lag(ev.time_waited_micro) over (order by snap_id)/1000/1000,2) time_waited_sec
,numtodsinterval((ev.time_waited_micro-lag(ev.time_waited_micro) over (order by snap_id))/1000/1000,'SECOND') total_wait
,round(((ev.time_waited_micro-lag(ev.time_waited_micro) over (order by snap_id))/(ev.total_waits-lag(ev.total_waits) over (order by snap_id)))/1000,2) avg_wait_ms
from dba_hist_system_event ev join dba_hist_snapshot s using(dbid,snap_id,instance_number)
where event_name like 'db file sequential read'
and end_interval_time between to_date('2021-05-19 10:00','YYYY-MM-DD HH24:MI') and to_date('2021-05-24 16:00','YYYY-MM-DD HH24:MI');

## Average event time from OEM
select avg(average) from (
select to_char(rollup_timestamp,'DD-MM-YYYY HH24:mi') tim,average from MGMT$METRIC_HOURLY
where target_name ='UATACP1M.apobank.lan'
and column_label = 'Average Wait Time (millisecond)'
and lower(key_value) ='db file sequential read'
and rollup_timestamp between to_date('13.05.2021 13:00','DD.MM.YYYY HH24:Mi') and to_date('14.05.2021 05:00','DD.MM.YYYY HH24:mi') )

select --s.end_interval_time,ev.event_name,ev.total_waits,ev.time_waited_micro
  min(end_interval_time),max(end_interval_time)
  ,round((max(time_waited_micro)-min(time_waited_micro))/(max(total_waits)-min(total_waits))/1000,2)  avg_wait
from dba_hist_system_event ev join dba_hist_snapshot s using(dbid,snap_id,instance_number)
where event_name like 'db file sequential%'
  and end_interval_time between to_date('2021-05-17 18:00','YYYY-MM-DD HH24:MI') and to_date('2021-05-18 07:01','YYYY-MM-DD HH24:MI')
  --and snap_id between 173 and 186
  ;


   
---######### DBA_HIST_SYSSTAT########----------


select * from 
where stat_name ='user I/O wait time';

--dokladnie
  SELECT a.snap_id, a.VALUE, to_char(b.begin_interval_time, 'YYYY-MM-DD')
    FROM (SELECT a.snap_id snap_id, (a.VALUE - b.VALUE) VALUE
            FROM DBA_HIST_SYSSTAT a, DBA_HIST_SYSSTAT b
           WHERE     a.snap_id = b.snap_id + 1
                 AND a. stat_name ='user I/O wait time'
                 AND b. stat_name ='user I/O wait time') a,
         DBA_HIST_SNAPSHOT b
   WHERE a.snap_id = b.snap_id
ORDER BY 1 DESC;

  --average daily
  SELECT TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD'),round( AVG (a.VALUE), 2)
    FROM (SELECT a.snap_id snap_id, (a.VALUE - b.VALUE) VALUE
            FROM DBA_HIST_SYSSTAT a, DBA_HIST_SYSSTAT b
           WHERE     a.snap_id = b.snap_id + 1
                 AND a. stat_name ='user I/O wait time'
                 AND b. stat_name ='user I/O wait time') a,
         DBA_HIST_SNAPSHOT b
   WHERE a.snap_id = b.snap_id
GROUP BY TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD')
ORDER BY 1 asc;
  
   
  SELECT *
    FROM DBA_HIST_ACTIVE_SESS_HISTORY
   WHERE sample_time BETWEEN TO_TIMESTAMP ('2010-06-17 11:20:00',
                                           'YYYY-MM-DD HH24:mi:ss')
                         AND TO_TIMESTAMP ('2010-06-17 12:10:00',
                                           'YYYY-MM-DD HH24:mi:ss')
         AND session_type = 'BACKGROUND'
         AND program LIKE '%CKPT%'
ORDER BY sample_time ASC


--average dla poszczegolnych instancji
  SELECT TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD'),
         ROUND (AVG (a.time / a.waits) / 1000, 2)
    FROM (SELECT a.snap_id snap_id,
                 (a.total_waits - b.total_waits) waits,
                 (a.time_waited_micro - b.time_waited_micro) time
            FROM DBA_HIST_SYSTEM_EVENT a, DBA_HIST_SYSTEM_EVENT b
           WHERE     a.snap_id = b.snap_id + 1
                 AND a.event_name = 'log file sync'
                 AND b.event_name = 'log file sync') a,
         DBA_HIST_SNAPSHOT b
   WHERE a.snap_id = b.snap_id
GROUP BY TO_CHAR (b.begin_interval_time, 'YYYY-MM-DD')
ORDER BY 1 ASC;

select tab.*, tabb.begin_interval_time from 
(select  a.snap_id,(sum(a.phyrds)-sum(b.phyrds))/ (sum(a.readtim)-sum(b.readtim)) from DBA_HIST_FILESTATXS a , DBA_HIST_FILESTATXS b
where a.snap_id -1= b.snap_id  
and a.tsname = 'FUNSCAN_DATA'
and b.tsname = 'FUNSCAN_DATA'
group by a.snap_id, b.snap_id
order by a.snap_id desc) tab, dba_hist_snapshot tabb
where tab.snap_id = tabb.snap_id;





  SELECT AVG (tab.VALUE), TO_CHAR (tabb.begin_interval_time, 'YYYY-MM-DD')
    FROM (  SELECT a.snap_id,
                   (SUM (a.readtim) - SUM (b.readtim))
                   / (SUM (a.phyrds) - SUM (b.phyrds) + 1)
                      VALUE
              FROM DBA_HIST_FILESTATXS a, DBA_HIST_FILESTATXS b
             WHERE     a.snap_id - 1 = b.snap_id
                   AND a.tsname = 'FUNSCAN_DATA'
                   AND b.tsname = 'FUNSCAN_DATA'
          GROUP BY a.snap_id, b.snap_id
          ORDER BY a.snap_id DESC) tab,
         dba_hist_snapshot tabb
   WHERE tab.snap_id = tabb.snap_id
GROUP BY TO_CHAR (tabb.begin_interval_time, 'YYYY-MM-DD')
ORDER BY 2 ASC;


## to check
select /*+ PARALLEL(4) DYNAMIC_SAMPLING(9) */ *
from ( select
current_timestamp ts,
(select owner || '.' || object_name from dba_objects where object_id = plsql_entry_object_id) entry_prc,
(select nvl((select owner||'.'||object_name from dba_objects where object_id = program_id),to_char(program_id))||' #'||program_line# from v$sqlarea where sql_id = d.sql_id) sql_src,
case
when plsql_subprogram_id is not null
then
(select owner
|| '.'
|| object_name
|| '.'
|| procedure_name
|| ' ('
|| overload
|| ')'
from dba_procedures
where object_id = plsql_object_id and subprogram_id = plsql_subprogram_id)
else
(select owner || '.' || object_name
from dba_objects
where object_id = plsql_object_id)
end
prc,
d.*
from (
select
sql_opname,
plsql_object_id,
plsql_subprogram_id
, round(count(*) / max(count(*)) over () * 100,2) pct_cnt
, count(*) cnt
, round(count(distinct sample_time) / max(count(distinct sample_time)) over () * 100,2) pct
, count(distinct sample_time) ct,
count (distinct sql_id) ct_sql,
count (distinct sql_exec_id) ct_sql_exec,
count(distinct instance_number||'.'||session_id||'.'||d.session_serial#||'.'|| xid) ct_trx,
sql_plan_hash_value,
sql_id,
sql_plan_line_id,
sql_plan_operation,
sql_plan_options,
min(session_id||'.'||d.session_serial#) sid,
nullif(max(session_id||'.'||d.session_serial#),min(session_id||'.'||d.session_serial#)) sid_,
nvl(event,'cpu') event,
-- min(p2), nullif(max(p2),min(p2)),
round(min(pga_allocated)/(1024*1024*1024),1) min_pga_gb,
round(max(pga_allocated)/(1024*1024*1024),1) max_pga_gb,
round(avg(pga_allocated)/(1024*1024*1024),1) avg_pga_gb,
round(max(temp_space_allocated)/(1024*1024*1024),1) max_temp_gb,
min(event) min_evt, nullif(max(event),min(event)) max_evt,
min(module) min_module, nullif(max(module),min(module)) max_module,
min(d.action) min_action, nullif(max(d.action),min(d.action)) max_action,
min(program) min_program, nullif(max(program),min(program)) max_program,
TO_CHAR(min(sample_time),'YYMMDD HH24:MI:SS') from_time, TO_CHAR(max(sample_time),'YYMMDD HH24:MI:SS') to_time,
plsql_entry_object_id,
case
when grouping (sql_plan_line_id) > 0
then
coalesce ( (select sql_text
from dba_hist_sqltext
where sql_id = d.sql_id and rownum = 1),
(select sql_fulltext
from v$sqlarea
where sql_id = d.sql_id))
end
sqltext
from dba_hist_active_sess_history d
-- from (select 1 instance_number, v.* from v$active_session_history v) d
where 1=1
and  d.sample_time between sysdate-1 and sysdate
and session_type != 'BACKGROUND'
group by  
grouping sets (
rollup ( plsql_entry_object_id, plsql_object_id, plsql_subprogram_id),
rollup ( plsql_entry_object_id, sql_opname,sql_plan_hash_value,sql_id,(sql_plan_line_id, sql_plan_operation, sql_plan_options),nvl(event,'cpu'))
)
) d
order by
-- cnt desc,
ct desc, cnt desc,
ct_sql desc,
ct_sql_exec desc,
ct desc,
plsql_object_id nulls first,
plsql_subprogram_id nulls first,
sql_plan_hash_value nulls first,
sql_id nulls first,
sql_plan_line_id nulls first)
where rownum <= 30000
;
