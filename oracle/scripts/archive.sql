col name format a70
select * from (select name, thread#, sequence#, first_time from v$archived_log order by 3 desc)
where rownum <10
/
