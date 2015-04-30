
set feed off;
set pagesize 10000;
set wrap off;
set linesize 200;
set heading on;
set tab on;
set scan on;
set verify off;
--
--spool show_logswitches.lst

ttitle left 'Redolog File Status from V$LOG' skip 2

select group#, sequence#, thread#,
       Members, archived, status, first_time, bytes/1024/10024 "size_MB"
  from v$log;

ttitle left 'Redolog file names' skip 2

select group#, member from v$logfile;

ttitle left 'Number of Logswitches per Hour' skip 2

select to_char(first_time,'YYYY.MM.DD') day,
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'00',1,0)),'99') "00",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'01',1,0)),'99') "01",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'02',1,0)),'99') "02",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'03',1,0)),'99') "03",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'04',1,0)),'99') "04",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'05',1,0)),'99') "05",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'06',1,0)),'99') "06",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'07',1,0)),'99') "07",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'08',1,0)),'99') "08",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'09',1,0)),'99') "09",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'10',1,0)),'99') "10",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'11',1,0)),'99') "11",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'12',1,0)),'99') "12",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'13',1,0)),'99') "13",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'14',1,0)),'99') "14",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'15',1,0)),'99') "15",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'16',1,0)),'99') "16",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'17',1,0)),'99') "17",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'18',1,0)),'99') "18",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'19',1,0)),'99') "19",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'20',1,0)),'99') "20",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'21',1,0)),'99') "21",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'22',1,0)),'99') "22",
       to_char(sum(decode(substr(to_char(first_time,'DDMMYYYY:HH24:MI'),10,2),'23',1,0)),'99') "23"
  from v$log_history
where first_time >= TRUNC ( SYSDATE - 14 )
 group by to_char(first_time,'YYYY.MM.DD')
order by 1;


ttitle left 'Redo size history' skip 2
set pagesize 1000

SELECT ROUND( (  COUNT(*) * (SELECT MIN ( bytes ) FROM v$log ))/1024/1024 ) as REDO_SIZE_MB, TO_CHAR( first_time,'yyyy-mm-dd') "DAY"
 FROM v$log_history
WHERE first_time >= TRUNC ( SYSDATE - 14 )
GROUP BY TO_CHAR( first_time,'yyyy-mm-dd')
ORDER BY 2; 

ttitle left 'AVARAGE DAILY REDO 14 DAYS' skip 2
select ROUND ( avg ( redo_size_mb ) , 0 )  ,ROUND ( MAX ( redo_size_mb ) , 0 ) , ROUND ( MIN ( redo_size_mb ) , 0 )
from
(
SELECT ROUND( (  COUNT(*) * (SELECT MIN ( bytes ) FROM v$log ))/1024/1024 ) as REDO_SIZE_MB,TO_CHAR( first_time,'yyyy-mm-dd') "DAY"
 FROM v$log_history
 WHERE first_time >= TRUNC ( SYSDATE - 14 )
GROUP BY TO_CHAR( first_time,'yyyy-mm-dd')
ORDER BY 2
);


ttitle left '############# V$INSTANCE_RECOVERY #########################' skip 2
SELECT  RECOVERY_ESTIMATED_IOS, ACTUAL_REDO_BLKS, TARGET_REDO_BLKS, 
LOG_CHKPT_TIMEOUT_REDO_BLKS
FROM SYS.V_$INSTANCE_RECOVERY;


SELECT 
   FAST_START_IO_TARGET_REDO_BLKS, TARGET_MTTR, ESTIMATED_MTTR, OPTIMAL_LOGFILE_SIZE, ESTD_CLUSTER_AVAILABLE_TIME
   FROM SYS.V_$INSTANCE_RECOVERY;

