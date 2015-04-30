set serveroutput on
alter session set nls_date_format='yyyy-mm-dd hh24:mi:ss';
prompt "####current time ########################"
select sysdate from dual;

prompt "####datafiles ########################"
col file# format 999
col name format a55
col CHECKPOINT_CHANGE# format 99999999999999
select file#,name,checkpoint_time,CHECKPOINT_CHANGE# from v$datafile order by CHECKPOINT_CHANGE#;


col first_change# format 9999999999999
prompt "####online logfiles ########################"
select * from v$log order by thread#;

prompt "####controlfile ########################"

exec adm_package.print_Table ('select CURRENT_SCN,CHECKPOINT_CHANGE#,ARCHIVELOG_CHANGE# from v$database');

prompt "####change to recover########################"
select current_scn-CHECKPOINT_CHANGE# from v$database;

