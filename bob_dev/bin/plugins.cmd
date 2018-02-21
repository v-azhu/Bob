REM ###########################################################################
REM #  
REM # Author      : Awen zhu
REM # CreateDate  : 2015-3-20
REM # Description : Raid deploy instance, Runs cmd provided by user.
REM # ChangeHist  : 2012-3-20 Init checkin.
REM #
REM # Depedencies : this plug in instance runs user command on Bob server.
REM #				
REM ###########################################################################

echo off
@set _MsgID=%1
@set _BundleName=%2
@set env=%3
@set _cmd=%4
@set _BobRoot=D:\Bob
@set _BundleRootDir=D:\raids
@cd /d %_BundleRootDir%
@if exist %_BundleName% rmdir /S /Q %_BundleName%
@if not exist %_BundleName%\BusinessSystems\Common\DBBuild\db\release\ApplyBundledHotfixes_LOG md %_BundleName%\BusinessSystems\Common\DBBuild\db\release\ApplyBundledHotfixes_LOG
@cd %_BundleName%\BusinessSystems\Common\DBBuild\db\release\ApplyBundledHotfixes_LOG
echo on

set path=%_BobRoot%\bin;%path%

rem set envronment variables
FOR /F "delims=" %%I IN ('perl -e "use lib '%_BobRoot%/lib';use BundleComm; my $BC = BundleComm->new('%_BobRoot%\\conf\\XConfig.xml'); print $BC->getAccountMap('%env%');"') DO %%I
@echo Envrionment variables > log.txt
@echo Env=%env% >> log.txt
@echo EnvName=%envName% >> log.txt
@echo Repository=%repository% >> log.txt
@echo BO_User=%BO_User% >> log.txt
@echo DB2_User=%DB2_User% >> log.txt
@echo Infa_User=%Infa_User% >> log.txt
@echo CTM_User=%CTM_User% >> log.txt
@echo cmd=%_cmd% >> log.txt
set _cmd=%_cmd:"=%

%_cmd% >> log.txt 2>&1

@if %errorlevel% equ 0 (
perl -e "use lib '%_BobRoot%/lib';use BundleComm; my $BC = BundleComm->new('','','%_BobRoot%\conf\CntlFile.pcf');$BC->sendMsg(%_MsgID%,'Status','Succeed');"
) else (
perl -e "use lib '%_BobRoot%/lib';use BundleComm; my $BC = BundleComm->new('','','%_BobRoot%\conf\CntlFile.pcf');$BC->sendMsg(%_MsgID%,'Status','Failed');"
goto problem )

:problem
echo There was an error duing runcmd!
exit 1
