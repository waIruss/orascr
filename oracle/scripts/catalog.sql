set verify off
undef what
set linesize 2000
col TABLE_NAME format a40
col COMMENTS format a80

/* Formatted on 2013-10-10 15:23:57 (QP5 v5.185.11230.41888) */
SELECT DISTINCT c.table_name, co.comments
  FROM all_catalog c, all_tab_comments co
 WHERE     UPPER (c.table_name) LIKE UPPER ('%&&what%')
       AND c.owner = co.owner
       AND c.table_name = co.table_name;
/

