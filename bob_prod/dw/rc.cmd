@REM This command is a wrapper to start rc.pl
@REM which is used to create a RC environment of BundleBuild
@echo off

set basename=%~dp0

if "%P4PORT%"=="" set P4PORT=perforce:1985
if "%p4charset%"=="" set p4charset=utf16le-bom
if "%p4commandcharset%"=="" set p4commandcharset=winansi
if "%p4config%"=="" set p4config=p4.ini

echo The follow P4 environment variables will be used:
echo p4port=%p4port%
echo p4charset=%p4charset%
echo p4commandcharset=%p4commandcharset%
echo p4config=%p4config%

perl %basename%\rc.pl %*

@echo on
