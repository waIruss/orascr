prompt =======standby redo
SELECT GROUP#, BYTES FROM V$STANDBY_LOG;

prompt =======waht was applied
SELECT SEQUENCE#,APPLIED FROM V$ARCHIVED_LOG ORDER BY SEQUENCE#;

