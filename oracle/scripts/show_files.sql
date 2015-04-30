PROMPT ########################################################################################################################
PROMPT ################################################# D A T A F I L E S ####################################################
PROMPT

COLUMN file_name 		format a50	heading 'File name'
column tablespace_name 		format a20	heading 'Tablespace name'
column (a.bytes/1024/1024)	format 999999	heading 'Size MB'
column substr(a.status,1,5)	format a6	heading 'Status'
column autoextensible		format a6 	heading 'Autoex'
column (a.maxbytes/1024/1024)   format 99999	heading 'Max MB'
COLUMN block_size		format 9999	heading 'Block size'
BREAK ON REPORT
COMPUTE SUM LABEL TOTAL OF (a.bytes/1024/1024) ON REPORT
select a.file_name, a.tablespace_name, (a.bytes/1024/1024), substr(a.status,1,5), a.autoextensible, (a.maxbytes/1024/1024), b.block_size
from dba_data_files a, dba_tablespaces b
where a.tablespace_name=b.tablespace_name
UNION
select a.file_name, a.tablespace_name, (a.bytes/1024/1024), substr(a.status,1,5), a.autoextensible, (a.maxbytes/1024/1024), b.block_size
from dba_temp_files a, dba_tablespaces b
where a.tablespace_name=b.tablespace_name
order by tablespace_name;


PROMPT ###########################################################################################################################
PROMPT ############################################### T A B L E S P A C E S######################################################

select tablespace_name, block_size, status, extent_management, initial_extent, round((next_extent/1024/1024),3) "Next Ext MB", min_extents, max_extents, segment_space_management 
from dba_tablespaces order by tablespace_name;

PROMPT ###########################################################################################################################
PROMPT ############################################### L O G F I L E #############################################################

COLUMN member format a50
select * from v$logfile;

PROMPT ###########################################################################################################################
PROMPT ############################################### C O N T R O L F I L E######################################################
COLUMN name format a50
select * from v$controlfile;


