@echo off
pushd "%~dp0"
echo %cd%
ratlperl ms_with_ftp.pl -debug -run
popd
