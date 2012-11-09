@echo off

SET _CLAN_=
SET _SITE_=
SET _CQ_USER_=
SET _CQ_PASS_=
SET _SCLASS_=
SET _SCLASSPATH_=
SET _REPLICA_=
SET _FAMILIES_=
SET _DROPSITE_=
SET _DROPSITEUSER_=
SET _DROPSITEPASS_=
SET _DROPSITEPATH_=
SET _WORKDIR_=%SYSTEMDRIVE%\cq_ms_work

REM DO NOT MODIFY BELOW HERE
SET _GETCMDS_=./getcmds.txt
SET _PUTCMDS_=./putcmds.txt

set _

goto :proc_in

:import
IF EXIST "%_WORKDIR_%" rd /S /Q "%_WORKDIR_%"
echo multiutil syncreplica -import -clan %_CLAN_% -site %_SITE_% -family %1 -u %_CQ_USER_% -p %_CQ_PASS_% -receive -sclass "%_SCLASS_%"

goto :EOF

:export
IF EXIST "%_WORKDIR_%" rd /S /Q "%_WORKDIR_%"
echo multiutil syncreplica -export -clan %_CLAN_% -site %_SITE_% -family %1 -u %_CQ_USER_% -p %_CQ_PASS_% -ship -workdir %_WORKDIR_% -sclass "%_SCLASS_%" %_REPLICA_%

goto :EOF

:proc_in
:: Process incoming data, get it from sftp and import into replica
REM Build commands to retrieve files
ECHO lcd "%_SCLASSPATH_%\incoming" > %_GETCMDS_%
ECHO mget "%_DROPSITEPATH_%/*.*" >> %_GETCMDS_%
ECHO exit >> %_GETCMDS_%
echo psftp.exe -pw %_DROPSITEPASS_% -b %_GETCMDS_% %_DROPSITEUSER_%@%_DROPSITE_% 2>&1  

REM Build commands to delete retrieved files
ECHO lcd "%_DROPSITEPATH_%/*.*" > %_GETCMDS_%
FOR /f %%a in ('dir /b %_SCLASSPATH_%\outgoing') DO @ECHO rm "%%a" >> %_GETCMDS_% 
ECHO exit >> %_GETCMDS_%
echo psftp.exe -pw %_DROPSITEPASS_% -b %_GETCMDS_% %_DROPSITEUSER_%@%_DROPSITE_% 2>&1

for %%a in (%_FAMILIES_%) do call :import %%a  

goto :proc_out

:proc_out
:: Process outgoing data, create packages and upload to sftp server
for %%a in (%_FAMILIES_%) do call :export %%a

@ECHO lcd "%_SCLASSPATH_%\outgoing" > %_PUTCMDS_%
@ECHO mput "%_DROPSITEPATH_%/*.*" >> %_PUTCMDS_%
@ECHO exit >> %_PUTCMDS_%
echo psftp.exe -pw %_DROPSITEPASS_% -b %_PUTCMDS_% %_DROPSITEUSER_%@%_DROPSITE_% 2>&1  
