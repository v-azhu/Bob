REM ###########################################################################
REM #  
REM # Author      : Awen zhu
REM # CreateDate  : 2012-3-27
REM # Description : Raid deploy instance, Create bundle and runs it for each given raids 
REM # ChangeHist  : 2012-3-27 Init checkin.
REM #
REM # Depedencies : For any raids release to DEV env, if there are Infa code included. 
REM #               InfaUser/InfaPass required accordingly. Otherwise, deploy process will
REM #				be stopped there by asking for login info
REM #				
REM ###########################################################################

echo off
@set _MsgID=%1
@set _BundleName=%2
@set _Raids=%3
@set env=%4
@set _RaidsType=%5
@set _InfaUser=%6
@set _InfaPass=%7
@set _BobRoot=D:\Bob
@set _BundleRootDir=D:\raids
@echo %P4PASSWD%|p4 login
@cd /d %_BundleRootDir%
@if exist %_BundleName% rmdir /S /Q %_BundleName%
@if not exist %_BundleName% md %_BundleName%
@cd %_BundleName%
@set bld_supress_pass=Nothing
echo on

FOR /F "delims=" %%I IN ('perl -e "use lib '%_BobRoot%/lib';use BundleComm; my $BC = BundleComm->new('%_BobRoot%\\conf\\XConfig.xml'); print $BC->getAccountMap('%env%');"') DO %%I

@IF /I "%_RaidsType%" == "edw" ( goto EDW ) else ( goto LDW )

:EDW
rem perl %_BobRoot%\bin\ebsbb.pl -raids %_Raids% -triagegroup edw -ignorever > %_BobRoot%\tmp\CBundle%_BundleName%.txt
perl %_BobRoot%\bin\BundleBuild_Dev.pl -raids %_Raids% -triagegroup edw -debug -ignorever> %_BundleRootDir%\StageLogs\CBundle%_BundleName%.txt 2>&1
@IF /I "%_Raids%" == "get" goto get
@if %errorlevel% neq 0 ( 
call perl -e "use lib '%_BobRoot%/lib';use BundleComm; my $BC = BundleComm->new('','','%_BobRoot%\\conf\\CntlFile.pcf');$BC->sendMsg(%_MsgID%,'CreateBundle','Failed');" 
goto problem )

goto Continue

:LDW
rem perl %_BobRoot%\bin\ebsbb.pl -raids %_Raids% -ignorever > %_BobRoot%\tmp\CBundle%_BundleName%.txt
perl %_BobRoot%\bin\BundleBuild_Dev.pl -raids %_Raids% -debug > %_BundleRootDir%\StageLogs\CBundle%_BundleName%.txt 2>&1
@IF /I "%3" == "get" goto get
@if %errorlevel% neq 0 ( 
call perl -e "use lib '%_BobRoot%/lib';use BundleComm; my $BC = BundleComm->new('','','%_BobRoot%\\conf\\CntlFile.pcf');$BC->sendMsg(%_MsgID%,'CreateBundle','Failed');" 
goto problem )

goto Continue

:Continue
@p4 logout
call perl -e "use lib '%_BobRoot%/lib';use BundleComm; my $BC = BundleComm->new('','','%_BobRoot%\\conf\\CntlFile.pcf');$BC->sendMsg(%_MsgID%,'CreateBundle','Succeed');"
@cd BusinessSystems\Common\DBBuild\db\HotFix\Bundles
rem copy dev script to release folder 
robocopy d:\perforce\v-azhu_perforce_1985\depot\tools\dev_dw\BuildScripts\ ../../release *.py

@if not exist "%_BundleRootDir%\%_BundleName%\BusinessSystems\Common\DBBuild\db\release\ApplyBundledHotfixes_LOG" mkdir %_BundleRootDir%\%_BundleName%\BusinessSystems\Common\DBBuild\db\release\ApplyBundledHotfixes_LOG
@if %errorlevel% neq 0 set errormessage="Failed to create hostfixes_log" && goto problem
@for %%i in (../../release/ApplyBundledHotfixes_LOG/*.*) do ( del /S /Q %%i )
rem call perl %_BobRoot%\bin\prepost.pl before %CD%
@if %errorlevel% neq 0 (
perl -e "use lib '%_BobRoot%/lib';use BundleComm; my $BC = BundleComm->new('','','%_BobRoot%\conf\CntlFile.pcf');$BC->sendMsg(%_MsgID%,'Status','Failed');"
set errormessage="Failed to apply hotfix" && goto problem )
call 19990101DMODSHotFixBundle.bat > %_BundleRootDir%\%_BundleName%\BusinessSystems\Common\DBBuild\db\release\ApplyBundledHotfixes_LOG\BundleScreenOutput.txt 2>&1
@if %errorlevel% equ 0 (
perl -e "use lib '%_BobRoot%/lib';use BundleComm; my $BC = BundleComm->new('','','%_BobRoot%\conf\CntlFile.pcf');$BC->sendMsg(%_MsgID%,'Status','Succeed');"
rem call perl %_BobRoot%\bin\prepost.pl after %CD% 
) else (
perl -e "use lib '%_BobRoot%/lib';use BundleComm; my $BC = BundleComm->new('','','%_BobRoot%\conf\CntlFile.pcf');$BC->sendMsg(%_MsgID%,'Status','Failed');"
goto problem )

:problem
echo There was an error duing deployment!
echo %errormessage%
exit 1
:get
@cd BusinessSystems\Common\DBBuild\db\HotFix\Bundles
