/*
--prompt "###########in datafiles ################"
set linesize 10000
col file_name format a50
set pagesize 100
set trimspool on
SELECT t.*,  max_file_size_mb -  ph_file_size_mb + free_space_in_file_mb AS ava_space_in_file_mb , autoextensible
FROM
(
SELECT file_name,
       round(bytes / 1024 / 1024) AS ph_file_size_mb,
       round(maxbytes / 1024 / 1024) AS max_file_size_mb,
       NVL( sum_free_space_mb , 0 ) AS free_space_in_file_mb,
       autoextensible
  FROM (SELECT file_id,
               round(SUM(bytes / 1024 / 1024)) AS sum_free_space_mb
          FROM dba_free_space
         GROUP BY file_id) fs,
       dba_data_files  DF                                                    
 WHERE df.file_id = fs.file_id(+)
) t
order by ava_space_in_file_mb;
*/


prompt "###########in tablespaces ################"
SELECT tablespace_name , SUM(ava_space_in_file_mb ) ava_space_in_tb
FROM
(
SELECT t.tablespace_name , t.file_name ,  max_file_size_mb -  ph_file_size_mb + free_space_in_file_mb AS ava_space_in_file_mb , autoextensible
FROM
(
SELECT tablespace_name,
       file_name,
       round(bytes / 1024 / 1024) AS ph_file_size_mb,
       round(maxbytes / 1024 / 1024) AS max_file_size_mb,
       NVL( sum_free_space_mb , 0 ) AS free_space_in_file_mb,
       autoextensible
  FROM (SELECT file_id,
               round(SUM(bytes / 1024 / 1024)) AS sum_free_space_mb
          FROM dba_free_space
         GROUP BY file_id) fs,
       dba_data_files  DF                                                    
 WHERE df.file_id = fs.file_id(+)
) t
order by ava_space_in_file_mb
) GROUP BY tablespace_name
order by ava_space_in_tb;



