-- my pid
 select
   p.spid,
   s.sid,
   s.serial#
 from
   sys.v_$session  s,
   sys.v_$process  p
 where
   s.sid = (select sid from sys.v_$mystat where rownum = 1) and
   p.addr = s.paddr;


--give ospid, get sid

select 
S.SID     ,
S.SERIAL# ,
p.SPID     UNIX_PR_Id
from v$process p,
     v$session s
  where p.ADDR = s.PADDR
     and p.spid=&podaj_unix_proc_id;

--give sid, get ospid
	 SELECT s.SID, s.serial#, p.spid unix_pr_id
  FROM v$process p, v$session s
 WHERE p.addr = s.paddr AND s.SID = &podaj_sid;
 