col dest_name format a30
col status format a10
col destination format a45
col alternate format a20
col valid_now format a9
select dest_name, status, destination, alternate, valid_now, error from v$archive_dest;

prompt ============ po awarii
prompt alter system set log_archive_dest_state_1=enable scope=both sid='*';
prompt alter system set log_archive_dest_state_2=alternate scope=both sid='*';

prompt
prompt ============ przed awaria
prompt alter system set log_archive_dest_state_1=defer scope=both sid='*';
prompt alter system set log_archive_dest_state_2=enable scope=both sid='*';

