col opname format a15
col target format a30

select sid, serial#, opname, target, start_time, time_remaining from v$session_longops
where time_remaining >0
order by target asc
/

