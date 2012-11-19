@echo off
REM Please fill out each of the SET statements below

REM Name of Clan to syncronized
SET _CLAN_=
REM Name of Site
SET _SITE_=
REM Name of ClearQuest user allowed to make syncronization packages
SET _CQ_USER_=
REM Password of above mentioned ClearQuest user
SET _CQ_PASS_=
REM Name of Storageclass to use
SET _SCLASS_=
REM Path to ms_ship folder of storage class, i.e. C:\ccshipping\ftp.sclass\ms_ship
SET _SCLASSPATH_=
REM Name of the replica 
SET _REPLICA_=
REM Name Clearquest replica family
SET _FAMILIES_=
REM server name to syncronize with. I.e. 12.13.14.15 or secret.server.com
SET _DROPSITE_=
REM User for drop site server
SET _DROPSITEUSER_=
REM Password of drop site server user
SET _DROPSITEPASS_=
REM The path on server to collect incoming packages from
SET _INGOING_DROP_PATH_=
REM The path on server to collect incoming packages from
SET _OUTGOING_DROP_PATH_=


REM DO NOT MODIFY BELOW HERE, 

SET _WORKDIR_=%SYSTEMDRIVE%\cq_ms_work
SET _GETCMDS_=./getcmds.txt
SET _PUTCMDS_=./putcmds.txt

GOTO proc_in

:import
:: Import sync packages that were downloaded in while executing the :proc_in LABEL
IF EXIST "%_WORKDIR_%" rd /S /Q "%_WORKDIR_%"
multiutil syncreplica -import -clan %_CLAN_% -site %_SITE_% -family %1 -u %_CQ_USER_% -p %_CQ_PASS_% -receive -sclass "%_SCLASS_%"

GOTO :EOF

:export
:: Create sync packages to be uploaded by :proc_out LABEL
IF EXIST "%_WORKDIR_%" rd /S /Q "%_WORKDIR_%"
multiutil syncreplica -export -clan %_CLAN_% -site %_SITE_% -family %1 -u %_CQ_USER_% -p %_CQ_PASS_% -ship -workdir %_WORKDIR_% -sclass "%_SCLASS_%" %_REPLICA_%

GOTO :EOF

:proc_in
:: Process incoming data, get it from sftp and import into replica
:: Build commands to retrieve files
@ECHO lcd "%_SCLASSPATH_%\incoming" > %_GETCMDS_%
@ECHO ls "%_INGOING_DROP_PATH_%/*" >> %_GETCMDS_%
@ECHO mget "%_INGOING_DROP_PATH_%/*" >> %_GETCMDS_%
@ECHO exit >> %_GETCMDS_%

:: Download files from server
psftp.exe -pw %_DROPSITEPASS_% -b %_GETCMDS_% %_DROPSITEUSER_%@%_DROPSITE_% > %_GETCMDS_%.tmp 2>&1  

:: Check downloaded files, match on name and size. If matching, prepare to remove the file on ftp server
del %_GETCMDS_%
FOR %%a in (%_SCLASSPATH_%\incoming\*) do FOR /F "tokens=1-8,*" %%d IN ('findstr /B /C:"-r" getcmds.txt.tmp') DO (
	IF "%%~nxa" EQU "%%l" (
		IF %%~za EQU %%h (
			@echo  Will remove: "%_INGOING_DROP_PATH_%/%%a"
			@ECHO rm "%_INGOING_DROP_PATH_%/%%a" >> %_GETCMDS_% 
		) ELSE (
			@echo.
			@echo  NOT removable: "%_INGOING_DROP_PATH_%/%%a"
			@echo.			
		)
	)
)
@ECHO exit >> %_GETCMDS_%

:: Talk to server again, delete the files we have downloaded succesfull (well, they match on name and size)
psftp.exe -pw %_DROPSITEPASS_% -b %_GETCMDS_% %_DROPSITEUSER_%@%_DROPSITE_% 2>&1

for %%a in (%_FAMILIES_%) do call :import %%a  

GOTO :proc_out

:proc_out
:: Process outgoing data, create packages and upload to sftp server

for %%a in (%_FAMILIES_%) do call :export %%a

:: Prepare to upload the newly created sync packages
@ECHO lcd "%_SCLASSPATH_%\outgoing" > %_PUTCMDS_%
@ECHO cd %_OUTGOING_DROP_PATH_% >> %_PUTCMDS_%
@ECHO mput * >> %_PUTCMDS_%
@ECHO ls >> %_PUTCMDS_%
@ECHO exit >> %_PUTCMDS_%
psftp.exe -pw %_DROPSITEPASS_% -b %_PUTCMDS_% %_DROPSITEUSER_%@%_DROPSITE_% > %_PUTCMDS_%.tmp   2>&1  

:: Check uploaded files, match on name and size. If matching, delete local file
FOR %%a in (%_SCLASSPATH_%\outgoing\*) do FOR /F "tokens=1-8,*" %%d IN ('findstr /B /C:"-r" putcmds.txt.tmp') DO (
	IF "%%~nxa" EQU "%%l" (
		IF %%~za EQU %%h (
			@echo  Will remove: "%%a"
			DEL "%%a"
		) ELSE (
			@echo.
			@echo  NOT removable: "%%a"
			@echo.			
		)
	)
)

:exit
