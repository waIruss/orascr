SELECT value FROM v$parameter WHERE name = 'control_management_pack_access';
SELECT snap_interval, retention FROM dba_hist_wr_control;
SELECT SYS_CONTEXT('USERENV','CON_NAME') con, COUNT(*) snaps,
       MIN(end_interval_time) oldest, MAX(end_interval_time) newest,
       COUNT(DISTINCT instance_number) insts
FROM   dba_hist_snapshot WHERE end_interval_time > SYSTIMESTAMP - 7;
SELECT 'SYS_TIME_MODEL' src, con_id, COUNT(*) cnt FROM dba_hist_sys_time_model
WHERE stat_name = 'DB time' GROUP BY con_id
UNION ALL
SELECT 'CON_SYS_TIME_MODEL', con_id, COUNT(*) FROM dba_hist_con_sys_time_model
WHERE stat_name = 'DB time' GROUP BY con_id;
