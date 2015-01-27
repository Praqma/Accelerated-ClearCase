@echo off

:: Customize next line to match the placement for Praqma ACC top-level folder
set PRAQMAPATH=\\%computername%\viewstor\stable
::
set LOG=%CLEARCASEHOME%\var\log\praqma_view_q.log
set OPTIONS= -logfile "%LOG%" %*

ratlperl "%PRAQMAPATH%\utils\view_q\view_q.pl" %OPTIONS%

if errorlevel 1 goto trouble
goto quit

:trouble
echo Praqma View Q experienced some problems. Please See %LOG%.

:quit