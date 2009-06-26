REM Prerequisits
@echo off
prompt $G
title view_q unittest
set nasince_date=2005-05-20
set test_log=C:\mikael-view_q\acc\view_q\unit_log.txt
set log_enable=-logfile %test_log%

echo on
echo basic functionallity
ratlperl view_q.pl
ratlperl view_q.pl -help
ratlperl view_q.pl -nologfile
ratlperl view_q.pl -nologfile -verbose
ratlperl view_q.pl -verbose
ratlperl view_q.pl -debug
ratlperl view_q.pl junk
type junk
ratlperl view_q.pl %log_enable%
type %test_log%
ratlperl view_q.pl -nologfile junk
ratlperl view_q.pl junk options
ratlperl view_q.pl -debug -noverbose -nologfile
ratlperl view_q.pl -help -lsq
ratlperl view_q.pl %log_enable% -lsq
ratlperl view_q.pl -nologfile -lsq
ratlperl view_q.pl -nologfile -verbose -lsq
ratlperl view_q.pl -verbose -lsq
ratlperl view_q.pl -debug -lsq

echo quarantine / [no]ignore / recover /  purge

ratlperl view_q.pl -q no_view %log_enable%
ratlperl view_q.pl -i no_view %log_enable%
ratlperl view_q.pl -r no_view %log_enable%
ratlperl view_q.pl -rec no_view %log_enable%
ratlperl view_q.pl -p no_view %log_enable%
ratlperl view_q.pl -lsquarantine -verbose %log_enable%
ratlperl view_q.pl -quarantine \\cccq7\cc_stg\views\CCCQ7\student\testa4.vws %log_enable%
ratlperl view_q.pl -lsquarantine -verbose %log_enable%
rgy_check -views
type \\cccq7\cc_stg\views\CCCQ7\student\testa4.vws\admin\.view_quarantine
ratlperl view_q.pl -recover \\cccq7\cc_stg\views\CCCQ7\student\testa4.vws %log_enable%
ratlperl view_q.pl -lsquarantine -verbose %log_enable%
rgy_check -views
type \\cccq7\cc_stg\views\CCCQ7\student\testa4.vws\admin\.view_quarantine
ratlperl view_q.pl -ignore testa4 %log_enable%
ratlperl view_q.pl -quarantine \\cccq7\cc_stg\views\CCCQ7\student\testa4.vws %log_enable%
ratlperl view_q.pl -noignore testa4 %log_enable%
ratlperl view_q.pl -ignore testa4 -region TEST %log_enable%
ratlperl view_q.pl -quarantine \\cccq7\cc_stg\views\CCCQ7\student\testa4.vws %log_enable%
ratlperl view_q.pl -noignore testa4 -region TEST %log_enable%
cleartool lsview
dir \\cccq7\cc_stg\views\CCCQ7\student\testa2.vws
ratlperl view_q.pl -quarantine \\cccq7\cc_stg\views\CCCQ7\student\testa2.vws %log_enable%
ratlperl view_q.pl -purge \\cccq7\cc_stg\views\CCCQ7\student\testa2.vws %log_enable%
cleartool lsview
dir \\cccq7\cc_stg\views\CCCQ7\student\testa2.vws
ratlperl view_q.pl -recover \\cccq7\cc_stg\views\CCCQ7\student\testa4.vws %log_enable%
ratlperl view_q.pl -purge \\cccq7\cc_stg\views\CCCQ7\student\testa4.vws %log_enable%

echo nasince

ratlperl view_q.pl -nasince %log_enable%
ratlperl view_q.pl -nasince blaha %log_enable%
ratlperl view_q.pl -nasince %nasince_date% %log_enable%
ratlperl view_q.pl -n %nasince_date% %log_enable%
ratlperl view_q.pl -na %nasince_date% %log_enable%
ratlperl view_q.pl -lsquarantine -verbose %log_enable%
ratlperl view_q.pl -ignore \\cccq7\cc_stg\views\CCCQ7\student\test2.vws %log_enable%
ratlperl view_q.pl -nasince %nasince_date% -autoquarantine %log_enable%
ratlperl view_q.pl -lsquarantine -verbose %log_enable%

echo lsquarantine

ratlperl view_q.pl -l %log_enable%
ratlperl view_q.pl -ls %log_enable%
ratlperl view_q.pl -lsquarantine -auto %log_enable%
ratlperl view_q.pl -lsquarantine -autor %log_enable%
ratlperl view_q.pl -lsquarantine -autop %log_enable%
ratlperl view_q.pl -quarantine \\cccq7\cc_stg\views\CCCQ7\student\testa2.vws %log_enable%
ratlperl view_q.pl -lsquarantine %log_enable%
ratlperl view_q.pl -lsquarantine -autorecover %log_enable%
ratlperl view_q.pl -lsquarantine %log_enable%
ratlperl view_q.pl -quarantine \\cccq7\cc_stg\views\CCCQ7\student\testa2.vws %log_enable%
ratlperl view_q.pl -lsquarantine %log_enable%
ratlperl view_q.pl -lsquarantine -autopurge %log_enable%
ratlperl view_q.pl -lsquarantine %log_enable%
