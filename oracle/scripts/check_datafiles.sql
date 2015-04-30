column error format a10
column online format a10
column online_status format a10
column name format a60
column "FILE#" format 999
column time format a20
col change# format 99999999999
alter session set NLS_DATE_FORMAT = 'mm-dd-yyyy HH24:mi:ss';

select b."FILE#", b."STATUS",a.change#,  a.online_status, a.error, b.CHECKPOINT_TIME, b.name from v$recover_file a right outer join v$datafile b
on  a.file# = b.file#
order by 1 asc;

-- check headers
col error format a20
col tablespace_name format a15
col status format a10
col error format a10
col name format a60

select file#, status, error, tablespace_name, checkpoint_time, name from
v$datafile_header;