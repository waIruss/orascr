prompt =================
prompt GENERAL
prompt =================
SELECT PROTECTION_MODE, PROTECTION_LEVEL,
 DATABASE_ROLE ROLE, SWITCHOVER_STATUS
FROM V$DATABASE;


prompt =================
prompt FROM PRIMARY / NOT SENT ARL
prompt =================
SELECT LOCAL.THREAD#, LOCAL.SEQUENCE# FROM 
 (SELECT THREAD#, SEQUENCE# FROM V$ARCHIVED_LOG WHERE DEST_ID=1) 
 LOCAL WHERE 
 LOCAL.SEQUENCE# NOT IN 
 (SELECT SEQUENCE# FROM V$ARCHIVED_LOG WHERE DEST_ID=2 AND 
 THREAD# = LOCAL.THREAD#);

prompt =================
prompt MAX ARCHIVED ARL
prompt =================
SELECT MAX(SEQUENCE#), THREAD# FROM V$ARCHIVED_LOG
WHERE RESETLOGS_CHANGE# = (SELECT MAX(RESETLOGS_CHANGE#) FROM V$ARCHIVED_LOG)
GROUP BY THREAD#;

col destination format a10
prompt =================
prompt ARCH DEST CONFIG
prompt =================
SELECT DESTINATION, STATUS, ARCHIVED_THREAD#, ARCHIVED_SEQ#
FROM V$ARCHIVE_DEST_STATUS
WHERE STATUS <> 'DEFERRED' AND STATUS <> 'INACTIVE';

prompt =================
prompt STANDBY REDO
prompt =================
SELECT GROUP#, BYTES FROM V$STANDBY_LOG;

prompt =================
prompt WHAT WAS APPLIED
prompt =================
select * from (
SELECT SEQUENCE#,APPLIED FROM V$ARCHIVED_LOG ORDER BY SEQUENCE# desc)
where rownum <10;

prompt =================
prompt STATUS
prompt =================
SELECT PROCESS, STATUS, THREAD#, SEQUENCE#, BLOCK#, BLOCKS FROM V$MANAGED_STANDBY;

prompt =================
prompt RECEIVED
prompt =================
SELECT THREAD#, SEQUENCE#, FIRST_CHANGE#, NEXT_CHANGE# FROM V$ARCHIVED_LOG;

prompt =================
prompt on standby
prompt =================
col value format a16

SELECT NAME, VALUE, DATUM_TIME FROM V$DATAGUARD_STATS;
