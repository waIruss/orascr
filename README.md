SELECT 'CON_SYSTEM_EVENT' src, COUNT(*) cnt FROM dba_hist_con_system_event
UNION ALL SELECT 'CON_SYSSTAT',     COUNT(*) FROM dba_hist_con_sysstat
UNION ALL SELECT 'OSSTAT',          COUNT(*) FROM dba_hist_osstat
UNION ALL SELECT 'IOSTAT_FUNCTION', COUNT(*) FROM dba_hist_iostat_function;

SELECT COUNT(*) cnt, MAX(cpu_utilization_limit) cpu_limit FROM dba_hist_rsrc_pdb_metric;

SELECT event_name, COUNT(*) cnt FROM dba_hist_con_system_event
WHERE  event_name IN ('db file sequential read','direct path read','log file sync','log file parallel write')
GROUP  BY event_name;

SELECT COUNT(*) snaps, MIN(end_interval_time) oldest, MAX(end_interval_time) newest FROM dba_hist_snapshot;
SELECT value cpu_count FROM v$parameter WHERE name = 'cpu_count';
