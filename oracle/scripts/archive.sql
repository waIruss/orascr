alter session set NLS_DATE_FORMAT = 'mm-dd-yyyy HH24:mi:ss';

col name format a65
col first_time format a20
select * from (select name, thread#, sequence#, first_time from v$archived_log order by 3 desc)
where rownum <10
/
