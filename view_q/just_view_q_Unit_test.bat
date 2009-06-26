REM Prerequisits
@echo off
prompt $G
title view_q unittest
set nasince_date=2005-01-01
set test_log=C:\mikael-view_q\acc\view_q\unit_log.txt
set log_enable=-logfile %test_log%

echo on
echo standart functionallity
ratlperl view_q.pl %log_enable%
ratlperl view_q.pl -lsquarantine %log_enable%
echo nasince tests
cleartool lsview -age
ratlperl view_q.pl -nasince %log_enable%
ratlperl view_q.pl -nasince blaha %log_enable%
ratlperl view_q.pl -nasince %nasince_date% %log_enable%
ratlperl view_q.pl -q %log_enable%
ratlperl view_q.pl -q \\cccq7\cc_stg\views\CCCQ7\student\testa4.vws %log_enable%
ratlperl view_q.pl -lsq %log_enable%
ratlperl view_q.pl -recover \\cccq7\cc_stg\views\CCCQ7\student\testa4.vws %log_enable%
ratlperl view_q.pl -lsq %log_enable%
ratlperl view_q.pl -nasince %nasince_date% -auto %log_enable%
ratlperl view_q.pl -nasince %nasince_date% -autoq %log_enable%
ratlperl view_q.pl -lsq  %log_enable%
ratlperl view_q.pl -lsq -autorecover %log_enable%
ratlperl view_q.pl -lsq %log_enable%
ratlperl view_q.pl -ignore testa2 %log_enable%
ratlperl view_q.pl -nasince 2005-01-01 -autoq %log_enable%
ratlperl view_q.pl -lsq  %log_enable%
cleartool mkview -tag view_test -stgloc -auto
ratlperl view_q.pl -purge \\cccq7\cc_stg\views\CCCQ7\student\view_test.vws %log_enable%
ct rmtag -view view_test
rgy_check -views
ratlperl view_q.pl -lsq %log_enable%
ratlperl view_q.pl -purge \\cccq7\cc_stg\views\CCCQ7\student\view_test.vws %log_enable%
cleartool mktag -view -tag view_test \\cccq7\cc_stg\views\CCCQ7\student\view_test.vws 
ratlperl  view_q.pl -q \\cccq7\cc_stg\views\CCCQ7\student\view_test.vws %log_enable%
ratlperl  view_q.pl -lsq %log_enable%
ratlperl  view_q.pl -lsq -autop %log_enable%
cleartool rmview \\cccq7\cc_stg\views\CCCQ7\student\view_test.vws

