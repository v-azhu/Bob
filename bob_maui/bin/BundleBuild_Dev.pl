=pod

NOTE: DO NOT CHECK IN WITH TYPE KTEXT... will not work if you do.

Tries to build the Hotfix bundle files (vbs, txt, bat and enlistment files) by looking at the Raid666.txt files
checked into //depot/dmo/dbbuild/hotfix/bundles/RaidFiles in Perforce.
Optionally, uses the enlistment created to Enlist and Build the DB directories if the corresponding options are passed

Since it calls DMOEnlist, this gets all the P4 checking that needs to be done for free from it

Operates only in the current directory

Calls the DMOEnlist for DBBuild to get the contents of //depot/dmo/dbbuild/hotfix/bundles/RaidFiles
If there are any errors from this Enlist effort, this program will abort with the corresponding message from DMOEnlist

Using the raids option, gets all the raid numbers that it has to use in building the bundle files
(This was changed to go to Raid5 DB instead of going to ExpITSystems raid)

Build the bundle files.

Do prelim checks on the bundle files and if the build option is specified, go ahead and use the enlistment file
built and call DMOEnlist and DMOBuild.

=cut

##########################################################################
# Include Packages
##########################################################################

# Try to get the Perforce.pm in your search path by adding every thing that doesn't include ~ from your %PATH%
BEGIN {
  push (@INC, grep {not /~/} map {split /;/} $ENV{"Path"});
}

use Perforce;       # Get common utilities.
use strict;
use File::Basename;    # Let's us tweak directory and unc paths and file names
use lib dirname(__FILE__);

use File::DosGlob 'glob'; # Override the standard glob which doesn't understand UNC's (\\a-christ\music\*.*)
              # Allows us to look for files with DOS syntax: Blort.*.txt
use Getopt::Long;     # Allows us to use GetOptions() to search @ArgV and name arguments like "-blort 23"
              # which would set $opt_blort = 23 See argument parsing section for more info.
use File::Find;      # Allows us to Traverse directory trees acting on files.
use FileHandle;
use File::Path qw(make_path);
use LWP::Simple;

&CheckModuleVersion("File::Path", 2.07);

use Util::DirCopy qw(dircopy);
use Data::Dumper;
use BundleBuild::Build qw(
  getBuildScriptOptions
  checkIncludingUniverse
  useBoedwbiarForUniverse
  extractJarMappings
  createViewForJars
  appendToFile);


##########################################################################
# Define variables
##########################################################################
my $BundleBatFile;
my @BundleBuildMessages;   # Initialize Warnings and Errors lists to be printed at the bottom of this message
my @BundleBuildWarnings;
my @BundleBuildErrors;
my $BundleFile;
my $BundleFilesDir;
my $BundleTxtFile;
my @BundleVBSFiles;
my $BundleJarsFile;
my $BusinessSystemsPath;
my $ChangeListFile;
my @ChangeLists;
my $client;
my $ClientRoot;
my $Command;
my $CommonBranch;
my $CurrentPath;
my %DeployObjects;
my $DBVersion;
my $DMOHotFixBundle;
my $p4_version;
my $Usage;
my $HotfixDate;
my %migrated_servers;
my $numberOfOpts;
my %objects;
my $opt_debug;
my $opt_help;
my $opt_hotfixdate;
my $opt_ignorever;
my $opt_IntegrateTo;
my $opt_raids;
my $opt_reportonly;
my $opt_triagegroup;
my $opt_update_servers;
my $opt_version;
my $opt_local;
my $opt_raidrepo;
my $opt_oldbounv;
my $OSQLArgs;
my $Raid;
my $resync;
my $Raiddatabase;
my $RaidFilesDir;
my $RaidPswd;
my @Raids;
my $RaidServer;
my $RelativeBundlePath;
my $RelativeRaidFilesPath;
my $ReleaseVehicle;
my $script_name;
my $SectionEnd;
my $SectionSeparator;
my $server;
my $TriageGroup;
my $view;
my $version;
my @WhoWhatWhere;

##########################################################################
# Initialize variables
##########################################################################
$client         = &GenerateRandomString(11);
$CommonBranch      = "DEV";
$DBVersion       = "27";
$DMOHotFixBundle    = "DMODSHotFixBundle";
$SectionSeparator    = "[Section:";
$SectionEnd       = "[End]";

@ChangeLists = ();
$CurrentPath      = `for \%i in (.) do \@echo \%~fni`;
chomp $CurrentPath;
$RelativeBundlePath   = "\\BusinessSystems\\common\\dbbuild\\db\\hotfix\\bundles";
$RelativeRaidFilesPath = "$RelativeBundlePath\\RaidFiles";
$BusinessSystemsPath  = $CurrentPath . "\\BusinessSystems";
$RaidFilesDir      = $CurrentPath . $RelativeRaidFilesPath; # Set the dir to search for Raid Files
$BundleFilesDir     = $CurrentPath . $RelativeBundlePath;  # set the dir to create the bundle files

$Raiddatabase      = "raid_dw";
$RaidServer       = "raid";
$RaidPswd        = "\@tt\@ck\?";
$OSQLArgs        = " -S $RaidServer -d $Raiddatabase -URAIDRO -P $RaidPswd -n -h-1 -s,";

$version        = '$Revision: #45 $';
$script_name      = $0;

$version    =~ s/^.*#(\d+).*?$/$1/;
$script_name  =~ s/^.*?(\w+\.\w+)$/$1/;

my $depot_path = $ENV{BUNDLE_BUILD_VER} =~/rc/i ? 
  "//depot/tools/dw-rc" : "//depot/tools/dw";

$p4_version = `p4 files $depot_path/$script_name 2>&1`;

if ( $p4_version =~ /P4PASSWD/ ) {
  &Die("Please login to perforce before running the bundle build tool.\n");
}

chomp ( $p4_version );
$p4_version =~ s/^.*#(\d+).*?$/$1/;

%migrated_servers    = (
   dnsqlmpt01   => 'chexsqclmpt01'
  , dnsqlebs02   => 'chexsqledw02'
  , dnsqlebs05   => 'chexsqlebs01'
);

##########################################################################
# Process command line
##########################################################################
$Usage = "Usage: perl [-w] $script_name
  [-help] [-debug] [-hotfixdate MM/DD/YYYY] [-raids RaidNumbers] [-reportOnly]
  [-ignorever] [-IntegrateTo] [-triagegroup] [-version] [-script PATH]
  [-raidrepo PATH] [-oldbounv]

-help:     If passed, prints out this message and exits successfully.

-debug:    Acts as if perl had been called with the -w option (Turn on
        warnings) and prints extensive debugging/logging messages.

-hotfixdate:  Uses this date for the bundle file names. If the below Raids
        option is not specified, Uses this date and searches the
        ExpRaid5 Raid DB for all raids that have a Hotfix date set to
        this date. These are the raids that will be used in building the
        bundle files. Note, this will also check for the Status of
        Resolved for these raids. If the Raids option is supplied, then
        the check of ExpRaid5 is skipped and only those specific raids
        are built The format for this date is MM/DD/YYYY (This is how it
        is currently entred in raid, per Tamara)

-raids:    Colon seperated list of raid numbers, if specified, these are the
        raids that will be built in the Bundle files. Expected values are
        numbers. Note when this is specified querying the Raid DB is
        entirely skipped.

-reportonly:  Will report on the status of the bugs from Raid DB for the given
        hotfix date and any errors or warnings and then exit. Nothing
        will be built. Do not specify this option along with Raids option

-ignorever:  Ignore version in workspace being different than perforce.

-IntegrateTo: Branch to auto integrate to, should only be used when creating a
        RC ready or Production ready bundle

-triagegroup: This specifies if the bundle is for LDW or EDW. If nothing is
        specified, LDW is used.

-update_servers
        This option is to be used for updating servers to their new
        names immediatly following a migration. It should only be used
        by the build team for a short period of time following a
        migration. The raid will fail if not using this flag. That
        should be a cue to the dev/test teams to have the code updated.

-version:   This returns the version of the script being run.
-script:    Using the local copy of BuildScript instead of syncing with
-raidrepo:   the local path where the files of RAIDxxx.txt are stored.
-oldbounv:   Allow using BOEDWBIAR for BO universes.
";

$numberOfOpts = @ARGV;
&GetOptions (
   "help|?"    , \$opt_help
  , "debug"     , \$opt_debug
  , "hotfixdate:s" , \$opt_hotfixdate
  , "raids:s"    , \$opt_raids
  , "reportonly"  , \$opt_reportonly
  , "ignorever"   , \$opt_ignorever
  , "IntegrateTo:s" , \$opt_IntegrateTo
  , "triagegroup:s" , \$opt_triagegroup
  , "update_servers", \$opt_update_servers
  , "v|version"   , \$opt_version
  , "script:s"   , \$opt_local
  , "raidrepo:s"  , \$opt_raidrepo
  , "oldbounv"   , \$opt_oldbounv
) or &Die("Error while parsing argument list for -options (you probably passed a bad -option):\n$Usage");

&Debug("Options returned from Getopt::Long:GetOptions() :
  -help      = $opt_help
  -debug     = $opt_debug
  -hotfixdate   = $opt_hotfixdate
  -raids     = $opt_raids
  -reportonly   = $opt_reportonly
  -ignorever   = $opt_ignorever
  -IntegrateTo  = $opt_IntegrateTo
  -triagegroup  = $opt_triagegroup
  -update_servers = $opt_update_servers
  -version    = $opt_version\n");

# -ignorever
if ($version != $p4_version and ! defined $opt_ignorever ) {
  print "You have version $version of the $script_name script. Perforce\n";
  print "has version $p4_version. Please sync your $depot_path\n";
  print "directory or use the -ignorever option.\n";
  exit(0);
}

# -version
if (defined $opt_version) {
  print "$script_name [Version: $version]\n\n";
  exit(0);
}

# -help
if ($numberOfOpts == 0 or defined $opt_help) {
  &Debug("Found option (-help) printing Usage and exiting");
  print "$Usage\n";
  exit(0);
}

# -debug
if (defined $opt_debug) {
  $^W = 1;
  &Debug("Found option (-debug) and turned on Debug() routine by setting \$^W");
}

# -hotfixdate
if (defined $opt_hotfixdate) {
  if ($opt_hotfixdate !~ /^(\d{2})\/(\d{2})\/(\d{4})$/) {
    &Die("Hotfixdate mentioned ($opt_hotfixdate) does not match the expected format. Expected date in MM/DD/YYYY format. Look at usage for more details.");
  }
  $HotfixDate = $3.$1.$2;  # create the YYYYMMDD format from the above match..
}else {
  $opt_hotfixdate = "01/01/1999";
  $HotfixDate = "19990101";
}

# -raids
if (defined $opt_raids) {
  if ($opt_raids !~ /^(\d+)(:\d+)*$/) { # match starting with a number, then unlimited combination of :Number
    &Die("Raids option specified ($opt_raids) does not fit the required format [nnn:nnn:nnn...].\n Usage: $Usage\n");
  }
  @Raids = split(":", $opt_raids);
}


# -reportonly
if (defined $opt_reportonly and defined $opt_raids) {
  &Die("Both the ReportOnly and the Raids option are specified. They are Mutually exclusive.\n$Usage\n");
}

# -triagegroup
if ( lc ( $opt_triagegroup ) eq "ldw" or ! defined $opt_triagegroup ) {
  $ClientRoot     = "//depot/dmo";
  $TriageGroup     = "DS Triage";
  $ReleaseVehicle   = "Emergency Hotfix";
} elsif ( lc ( $opt_triagegroup ) eq "edw" ) {
  $ClientRoot     = "//depot/edw";
  $TriageGroup     = "EDW Triage";
  $ReleaseVehicle   = "Hotfix";
} else {
  &Die("$Usage\n\nInvalid triagegroup specified. Please use ldw or edw.\n");
}

if (defined $opt_raidrepo) {
  $RaidFilesDir = $opt_raidrepo;
}

##########################################################################
# Main processing
##########################################################################
&Debug("RaidFilesDir: $RaidFilesDir, BundleFilesDir: $BundleFilesDir\n");
&Debug("HotfixDate: $HotfixDate\n");
&Debug("CommonBranch (used to get the raidfiles): $CommonBranch\n");

#createbusinesssystems folder
$Command = "md BusinessSystems";
system($Command);


# Set the bundle filename using the hotfix date
$BundleFile = $HotfixDate."DMODSHotFixBundle";
$ChangeListFile = $HotfixDate."DMODSHotFixBundleChangeList.txt";
$BundleJarsFile = $BundleFile.".jars";
$BundleBatFile = $BundleFile.".bat";
$BundleTxtFile = $BundleFile.".txt";
&Debug("BundleFile: $BundleFile, BundleChnageListFile: $ChangeListFile\n");
&Debug("BundleBatFile: $BundleBatFile, BundleTxtFile: $BundleTxtFile\n");

# If raids option was not specified, get the list of raids by querying ExpITSystems raid db
if (not defined $opt_raids) {
  open(SQL, "> QueryRaid.sql") or &Die("--- Error: Not able to open sql file to query raid DB. Error is $!\n");
  print SQL <<SQLEOF;
-- created by $0
set nocount on

select
   convert(varchar(6),BugID)
  , convert(varchar(13),SubStatus)
  , convert(varchar(13),Resolution)
  , convert(varchar(15),AssignedTo)
from dbo.BugStore
where TriageGrp   = '$TriageGroup'
and hotfixdate    = '$opt_hotfixdate'
and releaseVehicle  = '$ReleaseVehicle'
and milestone    = '4 QA'
and SubStatus    = '3 Complete'
order by Hotfixdate, BugID

go
SQLEOF
  my ($TmpFileName) = "QueryRaidResults.txt";

  $Command = "osql $OSQLArgs -i QueryRaid.sql > $TmpFileName";
  system($Command);

  @WhoWhatWhere = split(/\n/, `type $TmpFileName`);
}

print "\n--- Raids that have a Hotfix date of $opt_hotfixdate\n";
print ("RAIDNum SubStatus Resolution Assignee \n");
print ("------- ------  --------  -------- \n");

foreach (@WhoWhatWhere){
  my ($RaidNum, $issuestatus, $Resolution, $Assignee) = split /\,/, $_;
  $RaidNum =~ s/\s+//;
  # $issuestatus =~ s/\s+//;
  #$Resolution =~ s/\s+//;
  # $Assignee =~ s/\s+//;
  print "$issuestatus \n";
  print "$RaidNum $issuestatus $Resolution $Assignee \n";
  push (@Raids, $RaidNum);

}

# If option reportonly is specified exit
if ($opt_reportonly) {
  exit (0);
}

# Now run DMOEnlist to get DBBuild directory (to search for raid files)
# Create the P4.ini file.
&Debug("Creating P4.ini in current directory: $CurrentPath");
open (P4INI, ">P4.ini") or &Die("Unable to create file: P4.ini : $!");

print P4INI <<EOP4INI;
# Created by $0
P4PORT=$Perforce::P4Port
P4EDITOR=notepad.exe
P4CLIENT=$client
P4DIFF=windiff.exe
EOP4INI

close(P4INI) or &Die("Unable to close P4.ini file after writing: $!");

open(P4CLIENT, "> P4client.ini") or &Die("Unable to open the P4client.ini file created earlier in this script: $!");

print  P4CLIENT " ";

print P4CLIENT <<P4INI;
# Now all the P4 should be set, so create the P4Args variable
# Note that these args go right after the P4 and just before the command you want to run.
# A Perforce Client Specification.
#
# Client:   The client name.
# Update:   The date this specification was last modified.
# Access:   The date this client was last used in any way.
# Owner:    The user who created this client.
# Host:    If set, restricts access to the named host.
# Description: A short description of the client (optional).
# Root:    The base directory of the client workspace.
# AltRoots:  Up to two alternate client workspace roots.
# Options:   Client options:
#         [no]allwrite [no]clobber [no]compress
#         [un]locked  [no]modtime [no]rmdir
# LineEnd:   Text file line endings on client: local/unix/mac/win/share.
# View:    Lines to map depot files into the client workspace.
#
# Use 'p4 help client' to see more about client views and options.

Client: $client

Owner:

Host:

Description:
  Created by BundleBuild.pl.

Root:  $CurrentPath

Options:  noallwrite noclobber nocompress unlocked nomodtime normdir

LineEnd:  local

View:
P4INI

my (%bs_opts) = &getBuildScriptOptions($opt_local);
&Debug("Use $bs_opts{src} version of BuildScript in this path $bs_opts{path}\n"); 
if ($bs_opts{src} ne "local") {
  print P4CLIENT "  $bs_opts{path} //$client/BusinessSystems/common/DBBuild/db/release/...\n";
} 

if ( lc ( $opt_triagegroup ) eq "edw" ) {
  print P4CLIENT "  $ClientRoot/Informatica/$CommonBranch/db/release/... ";
  print P4CLIENT "  //$client/BusinessSystems/Informatica/db/release/...\n";
}

foreach $Raid ( @Raids ) {  
	Die("\n *** raid$Raid.txt must be \"text\" file type! *** \n") if (`p4 fstat -T headType $ClientRoot/Common/DBBuild/$CommonBranch/db/HotFix/Bundles/RaidFiles/raid$Raid.txt` !~ /text/i);
  print P4CLIENT "  $ClientRoot/Common/DBBuild/$CommonBranch/db/HotFix/Bundles/RaidFiles/raid$Raid.txt ";
  print P4CLIENT "  //$client/BusinessSystems/Common/DBBuild/db/HotFix/Bundles/RaidFiles/raid$Raid.txt\n";
}

close (P4CLIENT);

### Try to write out the existing P4client info to P4client.ini
&Debug("calling P4 client in order to create P4client.ini");
$Command = "P4 client -i < P4client.ini 2>&1";
&CallSystem("$Command") or &Die("Unable to create P4client.ini file with command: $Command");

#open P4Client.ini and add needed file defs.
$Command = "set p4client=$client&&p4 sync";
print "--- Running $Command to get Raid files ---\n";
&CallSystem("$Command") or &Die("Unable to run p4 sync");

# Using the local copy of BuildScripts instead of syncing with P4.
# This is for the development of bundle scripts.
if ($bs_opts{'src'} eq "local") {
  print "--- Copy the local BuildScripts from $bs_opts{path} ---\n";
  dircopy($bs_opts{path}, "$CurrentPath\\BusinessSystems\\common\\DBBuild\\db\\release");
}

&InitializeBundleFiles();

# Run the subroutine BuildBundleFilesForRaid for each of the raid numbers that we have obtained, the subroutine, returns
# ErrorStrings, if there are errors for each raid and this is used to report errors later.

push (@BundleBuildMessages, &BundleJiraVerify(\@Raids));
push (@BundleBuildMessages, map {&BuildBundleFiles($_, $RaidFilesDir, \@ChangeLists)} @Raids);
push (@BundleBuildMessages, &WriteChangeLists(\@ChangeLists));

foreach (@BundleBuildMessages) {
  if (@$_[0] =~ /Error/i) {
    push (@BundleBuildErrors, @$_[1]);
  } else {
    push (@BundleBuildWarnings, @$_[1]);
  }
}
		
if (@BundleBuildErrors > 0 ) {
  &Die("\n **** There were Errors when creating the bundle files. Listed Below: **** \n" . join("\n", @BundleBuildErrors) . "\n **** Bundle Files are not fully built. ****\n");
}


# Finalize the bundle files, this should deal with anything that has to go at the end.. Like the goto exit stmt
# in the bat file etc.. Also close all the bundle files. No need to check of errors as the subroutine dies if there are any
&FinalizeBundleFiles();

# If there are no errors while bunding and if the build option has been specified, build away
print "--- Bundle Files Built Successfully ---\n";

print "--- CreateLabelDef ---\n";
# Now run DMOEnlist with the build option
print "$BundleFilesDir\\$ChangeListFile \n";
close(CHANGELISTFILE);

$Command = "perl -S CreateLabelDef.pl" .
      " -LabelName $BundleFile" .
      " -ChangeListFile \"$BundleFilesDir\\$ChangeListFile\"" .
      " -ClientName $client" .
      " -ClientRoot $ClientRoot" .
      " -Branch $CommonBranch" .
      " -IntegrateTo $opt_IntegrateTo" .
      " -Raids " . join ( ":", @Raids );
system($Command);

my $mappings = &extractJarMappings($BundleJarsFile);
my $size = keys(%$mappings);
if ($size > 0) {
  $resync = 1;
  $view = &createViewForJars("//$client/BusinessSystems/Common", $mappings);
  &appendToFile("P4Client.ini", $view);
}

$view = &GetDBBuildFiles();
if ( $view ) {
  $resync = 1;
  &appendToFile("P4Client.ini", $view);
}

&Debug("calling P4 client in order to create P4client.ini");
$Command = "P4 client -i < P4client.ini 2>&1";
system($Command);

&Debug("resyncing P4client to bundle label");
$Command = "set p4client=$client&&p4 sync \@$BundleFile";
system($Command);

if ($resync == 1) {
  for my $jars (keys(%$mappings)) {
    system("set p4client=$client&&P4 sync $jars 2>&1");
  }
  foreach my $file ( sort keys %objects ) {
    system("set p4client=$client&&P4 sync $file 2>&1");
  }
}


if ($opt_IntegrateTo) {
  &IntegrateFiles();
}

&CheckBOUniverse(\@BundleVBSFiles) if (@BundleVBSFiles > 0);

if (@BundleBuildWarnings > 0 ) {
  print "\n Please review the following warnings generated by bundlebuild: \n" . join("\n", @BundleBuildWarnings) . "\n\n";
}

print "--- Bundle for HotfixDate $HotfixDate built successfully.---\n";

exit(0);

##########################################################################
# Subroutines
##########################################################################

# Write bundle verification steps to ensure each jira has been signed off
sub BundleJiraVerify {
  my ($_Raids) = shift;    
  my @_ErrMsg = ();

  print BATFILE <<BATEOF;
rem ---------------------------------------------
rem Jira status verify
rem ---------------------------------------------

call cd %releasedir%
if exist %workon_home%\\Deploy (
  set pythoncmd=%workon_home%\\Deploy\\Scripts\\python
	goto completeJiraVerify
) else (
  set pythoncmd=python
)

if not exist %pythoncmd% (
  if "%envName%"=="dev" goto bypassJiraVerify
  if "%envName%"=="test" goto bypassJiraVerify
  goto Problem
)

for /f usebackq %%i in (`%pythoncmd% -c "import jira"^&echo .`) do if not "%%i"=="." (
  \@echo Python with python-jira must be installed to deploy to the requested %envName% environment
  cmd /c exit 2
  if not "%envName%"=="dev" (
    goto Problem
  )
)
cmd /c exit 0

for /f usebackq %%i in (`%pythoncmd% -c "import P4"^&echo .`) do if not "%%i"=="." (
  \@echo P4Python must be installed to deploy to the requested %envName% environment
  cmd /c exit 2
  if not "%envName%"=="dev" (
    goto Problem
  )
)
set rc=%errorlevel%&cmd /c exit 0
if not %rc%==0 (
  \@echo bypassing JiraVerify for dev deployment due to environment errors
  goto :bypassJiraVerify
)
:completeJiraVerify
BATEOF

  print BATFILE "%pythoncmd% JiraVerify.py ".join(" ",@$_Raids)." -e %envName%\n";
  print BATFILE <<BATEOF;
if errorlevel 1 goto Problem

:bypassJiraVerify
BATEOF
  return @_ErrMsg;
}

# Call this routine when you want to build the bundle files given a raid number
# This routine will try to get the files in the raidsdir that match the raidnnn format and then
# append the values to the necessary bundle files. If there are no files for a given raid, depending on the
# ignorestatus variable, will either die at that point or return an error
#
# Arg 1 Raid Raid number that you want built
#
# Returns: array of error messages or nothing depending on success/failure.
sub BuildBundleFiles {
  my ($_Raid) = shift;
  my ($_RaidFilesDir) = shift;
  my ($_ChangeLists) = shift;
  my @RaidFiles=();
  my @ErrMsg=();
  my $FileContents;
  my $InitializeBat;
  my $InitializeBatEnd;

  print "--- Processing Raid: $_Raid.\n";

  # Search in the Raid files directory, any files matching Raidnnn*.txt, if not found then return with an errormsg.

	my $_rfd = $RaidFilesDir;
	$_rfd =~ s/\\/\//g;

	@RaidFiles = glob "\"$_rfd/Raid$_.txt\" \"$_rfd/Raid$_\_*.txt\"";

  if(@RaidFiles < 1){
    push (@ErrMsg, ["Error", "\tRaid$_Raid: There are no files in $_RaidFilesDir matching the given Raid number"]);
    return @ErrMsg;
  }

  # For all the files that matched the Raidnnnn.txt filename, slurp the contents of each file into a variable, then from within
  # that variable you can regex parse sections of text and put it in approp. file
  # Note: We are not going to check for any section (vbcode, manualsteps etc) being present since no one section is mandatory
  foreach (sort {lc $a cmp lc $b} @RaidFiles) {  # simple ascii sorting nothing else fancy for now
    print "\t--- Processing Raid File: $_.\n";

    # Open the raid file, return error if not able to do so.
    if (not open(RAID, "< $_")) {
      push (@ErrMsg, ["Error", "\t RAID $_Raid: Not able to open Raid file $_"]);
      next;
    }
    # localize the change to input seperator (within braces), this is so that we can slurp the contents of the file to a variable
    {
      undef $/;
      $FileContents = <RAID>;
    }
    close(RAID);  # Close the raid file

    my @Section = split(/\Q$SectionSeparator\E\s*(.*?)\s*\]|\Q$SectionEnd\E\s*/is, $FileContents);
    my $SectionIdx=0;

		push (@ErrMsg, &InitializeRaid($_Raid));
		
    for my $index (1..$#Section) { 
      next unless $index%2;
      my $section=@Section[$index];
      $SectionIdx+=1;
  
      if ($section =~ /VBCode/i) 
      {
        push (@ErrMsg, &VBCode($_Raid, @Section[$index+1], $SectionIdx));
      }
      elsif ($section =~ /ManualSteps/i)
      {
        push (@ErrMsg, &ManualSteps($_Raid, @Section[$index+1], $SectionIdx));
      }
      elsif ($section =~ /BatFileContents/i)
      {
        push (@ErrMsg, &BatFileContents($_Raid, @Section[$index+1], $SectionIdx));
      }
      elsif ($section =~ /JavaDeployment/i)
      {
        push (@ErrMsg, &JavaDeployment($_Raid, @Section[$index+1], $SectionIdx));
      }
      elsif ($section =~ /ChangeLists/i) 
      {
				push (@ErrMsg, &GatherChangeLists($_Raid, @Section[$index+1], \@$_ChangeLists));
      }
      elsif ($section =~ /Jars/i)
      {
        push (@ErrMsg, &Jars($_Raid, @Section[$index+1], $SectionIdx));
      }
      else
      {
        push (@ErrMsg, ["Error", "\t RAID $_Raid: Invalid section: @Section[$index]"]);
      }
    }
		push (@ErrMsg, &FinalizeRaid($_Raid));
  }
	return @ErrMsg;
}
# Write deployment starting message and setlocal to protect environment.
sub InitializeRaid {
  my $_Raid = shift;    
  my @_ErrMsg = ();

  print BATFILE ":DEP$_Raid\n";
  print BATFILE "\@echo.\n";
  print BATFILE "\@echo ^<^<^<deployment:DEP$_Raid Starting^>^>^>\n";
	print BATFILE "\@echo to restart execute:\n";
	print BATFILE "\@echo   %0 DEP$_Raid\n";
	print BATFILE "setlocal EnableDelayedExpansion\n";
  print BATFILE "\@echo.\n";
  return @_ErrMsg;
}


# Write deployment success message for each raid
sub FinalizeRaid {
  my $_Raid = shift;    
  my @_ErrMsg = ();

  print BATFILE "endlocal\n";
  print BATFILE "\@echo.\n";
  print BATFILE "\@echo ^<^<^<deployment:$_Raid Success^>^>^>\n";
  print BATFILE "\@echo.\n";
	print BATFILE "cmd /c exit 0\n";
  return @_ErrMsg;
}

# Write Change Lists to 
#
# Returns error array
#
sub WriteChangeLists {
  my ($_ChangeLists) = shift;    # split on line breaks;
  my $PrevChangeList = 0;
  my @_ErrMsg = ();
	
	foreach (sort {@$a[0] <=> @$b[0]} @$_ChangeLists ) {
		if (@$_[0] != $PrevChangeList) {
      print "Adding changelist to list of ChangeLists: @$_[1]\n";
      print CHANGELISTFILE "@$_[0]\n";
    } else {
      push (@_ErrMsg, ["Warning", "Warning:\t Duplicate change eliminated: @$_[1]"]);
    }		
		
		$PrevChangeList = @$_[0];
  }

  return @_ErrMsg;
}

# Process VBCode section
#
# Returns error array
#
sub VBCode {
  my ($_Raid) = shift;
  my ($_Contents) = (shift)."\n";
  my ($_SectionIdx) = shift;
  my @_ErrMsg = ();

  my $BundleVBSFile="$HotfixDate$DMOHotFixBundle$_Raid"."_$_SectionIdx.vbs";
  return @_ErrMsg if ( $_Contents =~ /^\s*$/s );

  my $commentHeader = "''''''''''''''''''''Inserted by Bundlebuild.pl''''''''''''''''''''''''''''";
  my @Bundles = split(/^\s*(\QgoHotfixBundle.BundleHotfixAdd("\E.*\"\)|BOEDWUNV.*)\s*$/im, "$_Contents\n" );
  my @BundlesOut;
  my $HotfixFound="False";
  
  if ($#Bundles%2 == 0) {push(@Bundles,"");} # Add an odd entry to keep logic simple
  for my $index (1..$#Bundles) {
    next if $index%2 == 0; #skip even entries
    my $mlnSchemaName = "";
    my $mlnDatabaseName = "";
    my $mlnServerName = "";
    
    my @Lines = split ('\n', "@Bundles[$index-1]\n");
		
    if (@Bundles[$index-1] =~ /.*HotFixBundle.*/i) {
      $HotfixFound="True";
      
      foreach my $line (@Lines) {
        if ( $line =~ /goHotfixBundle.sRCSchemaName/i) {
          $mlnSchemaName = $line;
          $mlnSchemaName =~ s/sRC/sMLN/i;
        }
        if ( $line =~ /goHotfixBundle.sRCDatabaseName/i) {
          $mlnDatabaseName = $line;
          $mlnDatabaseName =~ s/sRC/sMLN/i;
        }
        if ( $line =~ /goHotfixBundle.srcServerName/i) {
          $mlnServerName = $line;
          $mlnServerName =~ s/sRC/sMLN/i;
          $mlnServerName =~ s/chelsqldw01/chelsqledw201/i;
          $mlnServerName =~ s/chelsqlnrt01/chessqlnrt201/i;
          $mlnServerName =~ s/chelsqlnrt02/chessqlnrt202/i;
          $mlnServerName =~ s/cheisqlnrt004/chelsqlnrt23\\ins1/i;
          $mlnServerName =~ s/chelsqlpmnt14/chelsqlpmnt16/i;
          $mlnServerName =~ s/RCEDW/MLNEDW/i;
        }

        if ( $line =~ /DeployObjects\s*\(\s*['"]([^'"]+)['"]\s*\)/i ) {
         $DeployObjects{$1} = 1;
        }
      }

      if ($mlnSchemaName ne "" || $mlnDatabaseName ne "" || $mlnServerName ne "") {
        if (($mlnSchemaName ne "" || $mlnDatabaseName ne "") && $mlnServerName ne "") {

          push (@Lines, $commentHeader);

          if ($mlnSchemaName ne "") {
            push (@Lines, $mlnSchemaName);
          }
          
          if ($mlnDatabaseName ne "") {
            push (@Lines, $mlnDatabaseName);
          }
          
          push (@Lines, $mlnServerName);
          push (@Lines, $commentHeader);
        }
        else {
          push (@_ErrMsg, ["Error", "---Error: Missing RC Environment for Hotfix Bundle ---"]);
          return @_ErrMsg;
        }
      }
    }
    
    push (@Lines, @Bundles[$index]);
    push (@BundlesOut, join("\n",@Lines));
  }
	
  print BATFILE <<BATFILEEOF;
\@echo ---------------------------------------------
\@echo Deploy $_Raid VBS object
\@echo ---------------------------------------------
call cd \%releasedir\%
Cscript ApplyBundledHotfixes.vbs $BundleVBSFile
if %errorlevel% neq 0 goto Problem
  
BATFILEEOF

  # Insert the contents of the vbs, bat and txt files that we got by parsing thru the raid file, store the enlistment
  # in a hash to uniquify it..
  push (@BundleVBSFiles, $BundleVBSFile);
  return &CreateBundleVBSFile($BundleFilesDir, $BundleVBSFile, \@BundlesOut, $_Raid, $_SectionIdx, $HotfixFound);
}

# Create the Bundle VBS File for the VBCode section
#
# Returns error array
#
sub CreateBundleVBSFile {
  my ($_BundleFilesDir) = shift;
  my ($_BundleVBSFile) = shift;
  my ($_Bundles) = shift;
  my ($_Raid) = shift;
  my ($_SectionIdx) = shift;
  my ($_HotfixFound) = shift;

  my @_ErrMsg = ();

  unlink "$_BundleFilesDir\\".$_BundleVBSFile if (-e "$_BundleFilesDir\\".$_BundleVBSFile);
  unless (open(VBSFILE, ">>$_BundleFilesDir\\$_BundleVBSFile"))
    {
    push (@_ErrMsg, ["Error", "---Error: Not able to open file $_BundleVBSFile in $_BundleFilesDir. Error is $!\n"]);
    return @_ErrMsg;
    }
  VBSFILE->autoflush(1); # physically write to the file immediately with the write command.. this is since we check the size at the end
  # Print contents into the vbs file
  if ($_HotfixFound eq "True") {
    print VBSFILE <<VBSEOF;
'
'***************************************************************************************
' VBS Script file for including the hotfix code that needs to be run
'***************************************************************************************

gsBundleName = replace(WScript.ScriptName,".vbs", "")
gsBuildType  = "hotfix"
gsDBRootDir  = "null"
gsDBVersion  = "$DBVersion"
gsUserName  = "null"
gsPassword  = "null"
gfFullCompile = "N"
gsOnErrorExit = "Y"

VBSEOF
  }
  print VBSFILE <<VBSEOF;
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'' VBS code for raid $_Raid section:$_SectionIdx
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
VBSEOF
  print VBSFILE join ("\n",@$_Bundles);
  print VBSFILE "\n";
  
  close(VBSFILE);

  # check success
  unless (-s "$_BundleFilesDir\\$_BundleVBSFile") 
    {
      push (@_ErrMsg, ["Error", "--Error in CreateBundleVBSFile. File size of $_BundleVBSFile is zero."]);
      return @_ErrMsg;
    }
  print "--- Successfully created BundleVBSFile: $_BundleVBSFile ---\n";
  
  return @_ErrMsg;
}
# Process ManualSteps section
#
# Returns error array
#
sub ManualSteps {
  my ($_Raid) = shift;
  my ($_Contents) = (shift)."\n";
  my ($_SectionIdx) = shift;
  my @_ErrMsg = ();
  return @_ErrMsg if ( $_Contents =~ /^\s*$/s );
  
  print TXTFILE "########################################################################\n";
  print TXTFILE "## Manual steps for raid $_Raid section: $_SectionIdx\n";
  print TXTFILE "########################################################################\n";
  print TXTFILE "$_Contents";

  return @_ErrMsg;
}

# Process BatFileContents section
#
# Returns error array
#
sub BatFileContents {
  my ($_Raid) = shift;
  my ($_Contents) = shift."\n";
  my ($_SectionIdx) = shift;

  return if ( $_Contents =~ /^\s*$/s );
	
	if ($_Contents =~ /(^\s*set\s*rc=%errorlevel%\n\s*if\s*errorlevel\s*\d?\s*goto\s*:\S*\s*\n)$/smi ) {
		&Die("\n\n\nBug detected in BatFileContents Section:\n  ".join("\n  ",split ('\n', $1))."\n\nShould be: 'set rc=%errorlevel%\&cmd /c exit %errorlevel%'\n\n");
	}
	if ($_Contents =~ /^\s*(:problem|:exit|:continue|:completeJiraVerify|:bypassJiraVerify)\s*$/smi ) {
		&Die("\n\n\nBug detected in BatFileContents Section:\n  $1 label is reserved for the deployment bundle\n\n");
	}

  print BATFILE "rem ########################################################################\n";
  print BATFILE "rem ## BAT code for raid $_Raid section:$_SectionIdx\n";
  print BATFILE "rem ########################################################################\n";
  print BATFILE "cd \%releasedir\%\n";
  print BATFILE "SET JIRA_NUM=$_Raid\n";
  print BATFILE "SET log=\%logdir\%\\\%envName\%_$_Raid"."_$_SectionIdx"."_BatFileContents.log\n";
  print BATFILE "$_Contents";
  return;
}

# Validate and Gather the Change Lists from the Change List section
#
# Returns error array
#
sub GatherChangeLists {
  my ($_Raid) = shift;
  my ($_Contents) = (shift)."\n";
  my $_ChangeLists = (shift);
  my @_ErrMsg = ();
	my $PrevChangeList = 0;
  
  foreach (grep (!/^\s*$/, split (/\r\n|\n\r|\n|\r/, $_Contents))) {
    if (!/^\s*(\d+)\s*(#.*|\s*)$/) { 
      push (@_ErrMsg, ["Error", "\t RaidFile $_: Cannot parse out the ChangeLists section. Either the section is missing or the [End] tag is missing"]);
    } elsif ($1 < $PrevChangeList) {
      push (@_ErrMsg, ["Error", "\tChangelist error: ChangeLists must be listed in ascending numerical order: "
       .$PrevChangeList.", ".($PrevChangeList = $1)]);
		} else {
      push (@$_ChangeLists, [$PrevChangeList = $1, $_] );
    }
  }			

  return @_ErrMsg;
}

# Process JavaDeployment section
#
# Returns error array
#
sub JavaDeployment {
  my ($_Raid) = shift;
  my ($_Contents) = (shift)."\n";
  my ($_SectionIdx) = shift;
  my $CurrentLine;
  my $JenkinsView;
  my $JenkinsProject;
  my $JenkinsBuild;
  my $JenkinsArtifact;
  my $JenkinsFile;
  my $JenkinsDeployScript;
  my $JavaDeployment;
  my $JavaDeploymentBatFile;
  my $url;
  my $destination_folder;
  my $destination;
  my $current_length;
	my $cmd;
  my @_ErrMsg = ();
  
  return if ( $_Contents =~ /^\s*$/s );

  my @JavaDeployments = split("\n", $_Contents);  # split on line breaks
  foreach $CurrentLine ( @JavaDeployments ) {
    $CurrentLine =~ s/\s*#.*$//;      # Strip comments
    next if ( $CurrentLine =~ /^\s*$/ );  # Skip empty lines
    if ( $CurrentLine =~ /^\s*([_\w]+)\s+([_\w]+)\s+(\d+)\s+([^\s]+)\s*$/ ) {
      $JenkinsView   = $1;
      $JenkinsProject  = $2;
      $JenkinsBuild   = $3;
      $JenkinsArtifact = $4;

      # Get deploy script name
      $JenkinsDeployScript = "install_$JenkinsView.sh";

      # Get filename only
      $JenkinsFile = $JenkinsArtifact;
      $JenkinsFile =~ s/^.*[\\\/]//;

      # Get files
      $url = "http://edw-build-test:8080/jenkins/view/$JenkinsView/job/$JenkinsProject/$JenkinsBuild/artifact/$JenkinsArtifact";
      $destination_folder = "$BusinessSystemsPath\\$JenkinsView\\$JenkinsProject";
      $destination = "$destination_folder\\$JenkinsFile";
      print "Getting $url\n";
      &make_path($destination_folder);
			if (-e $destination)
			{
				unlink $destination
			}
			$cmd = "cd \"$destination_folder\"\&wget $url -nv 2\>\&1 ";
	    print "$cmd\n";
      print `$cmd` . "\n";
      push ( @_ErrMsg, "Error code: $?, " . ", retrieving $url" ) unless ($? == 0);

      # Build batch file
      $JavaDeploymentBatFile .= "bash ssh_cmd.sh \"$JenkinsView\" \"if [ -e $JenkinsFile ]; then rm -f $JenkinsFile; fi;\"\n";
      $JavaDeploymentBatFile .= "if errorlevel 1 goto Problem\n\n";

      $JavaDeploymentBatFile .= "bash scp_cmd.sh \"$JenkinsView\" \"\%BusinessSystemsdir\%\\$JenkinsView\\$JenkinsProject\" \"$JenkinsFile\"\n";
      $JavaDeploymentBatFile .= "if errorlevel 1 goto Problem\n\n";

      $JavaDeploymentBatFile .= "bash ssh_cmd.sh \"$JenkinsView\" \"if [ -e $JenkinsFile ]; then rm -f $JenkinsDeployScript; fi;\"\n";
      $JavaDeploymentBatFile .= "if errorlevel 1 goto Problem\n\n";

      $JavaDeploymentBatFile .= "bash scp_cmd.sh \"$JenkinsView\" \"\%releasedir\%\" \"$JenkinsDeployScript\"\n";
      $JavaDeploymentBatFile .= "if errorlevel 1 goto Problem\n\n";

      $JavaDeploymentBatFile .= "bash ssh_cmd.sh \"$JenkinsView\" \"chmod 755 $JenkinsDeployScript\"\n";
      $JavaDeploymentBatFile .= "if errorlevel 1 goto Problem\n\n";

      $JavaDeploymentBatFile .= "bash ssh_cmd.sh \"$JenkinsView\" \"./$JenkinsDeployScript \%JIRA_NUM\% $JenkinsFile\"\n";
      $JavaDeploymentBatFile .= "if errorlevel 1 goto Problem\n\n";

      $JavaDeploymentBatFile .= "\@echo connect to \%prodedw\% user \%DB2_USER\% using \%DB2_PASS\%; > log_deployment.sql\n";
      $JavaDeploymentBatFile .= "\@echo call dbadm.DBBuildObjectSet ('$JenkinsView', '$JenkinsProject', '$JenkinsFile', current timestamp, '%JIRA_NUM%'); >> log_deployment.sql\n";
      $JavaDeploymentBatFile .= "\@echo terminate; >> log_deployment.sql\n\n";

      $JavaDeploymentBatFile .= "db2cmd -w -c \"db2 -tsvf log_deployment.sql && del log_deployment.sql\"\n";
      $JavaDeploymentBatFile .= "if errorlevel 1 goto Problem\n\n";
    } else {
      push (@_ErrMsg, ["Error", "\t RaidFile $_: Invalid line in JavaDeployment section: $CurrentLine"]);
    }
  }
  
  if ( $JavaDeploymentBatFile !~ /^\s*$/s ) {
    print BATFILE "rem ########################################################################\n";
    print BATFILE "rem ## Java code for raid $Raid\n";
    print BATFILE "rem ########################################################################\n";
    print BATFILE "$JavaDeploymentBatFile";
  }
  
  return @_ErrMsg;
}
# Process Jars section
#
sub Jars {
  my ($_Raid) = shift;
  my ($_Contents) = (shift)."\n";
  return if ( $_Contents =~ /^\s*$/s );

  print JARSFILE /\Q$_Contents\E/;
  return;
}

# Call this routine when you want to finialize the bundle files creation
# This routine will insert anything that needs to be inserted at the end of the bundle files (like defining exit lable for bat file)
# and then close the bundle files
#
# Arguments: None
#
# Returns: Nothing
sub FinalizeBundleFiles {

  # print to batfile, cleanup by closing the bundle files.

  if (not defined fileno BATFILE) {  # if the filehandle is not open, it is a problem since we need to write to it, so die
    &Die("-- Error: Finialize was not able to write to the bundle batch file since the file handle was not defined. This is mostly a coding error.");
  }
  if (not defined fileno CHANGELISTFILE) {  # Same as above, we need to write to it so die if you cant find the handle
    &Die("-- Error: Finialize was not able to write to the bundle Enlist file since the file handle was not defined. This is mostly a coding error.");
  }

  # Now write to the bat file the closing stuff
  print BATFILE <<BATEOF;

goto exit

:Problem
\@echo There was a problem during the hotfix
call cd \%BundleDir\%
exit /b 1

:exit

call cd \%BundleDir\%
BATEOF

  # Now close the files
  close(BATFILE);
  close(CHANGELISTFILE);
  close(JARSFILE) if (defined fileno JARSFILE);
  close(TXTFILE) if (defined fileno TXTFILE); # dont care as of now, if this was closed before

  # Now, before finishing up check to see that the enlistment file has something in it, or die
  #(-s "$BundleFilesDir\\$ChangeListFile") or &Die("--Error: Enlistment file $BundleFilesDir\\$ChangeListFile is empty.");
}

# Validates the YYYYMMDD between 1980 and 2029 in Argument1
# Returns 1 if the YYYYMMDD is valid
# For invalid dates, it writes a message with ErrorLog and returns 0.
#
# Argument1: $YYYYMMDD - a string containing the Year, Month, Day you want to validate
sub YYYYMMDDValidate(){
  my($YYYYMMDD) = @_;

  my($SubName);     # Name of this routine
  my($MM, $DD, $YYYY);  # Date parts to help with padding the date.

  my(@Day);       # Array of days in months.
  my($ReturnStatus);   # The Value returned for this routine

  $ReturnStatus = 0;
  $SubName = "NTBatch::YYYYMMDDValidate";
  @Day = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

  # Separate the values representing MM, DD and YYYY
  if ($YYYYMMDD =~ m/^(\d\d\d\d)(\d\d)(\d\d)$/){
    $YYYY = $1;
    $MM = $2;
    $DD = $3;

    # Remember a leap year every 4 years based on your YYYY
    $Day[1] = 29 if ($YYYY % 4 == 0);

    # Validate the date itself now.
    if ($YYYY < 1980 or $YYYY > 2029){
      &Die("---Error: Bad HotfixDate ($YYYYMMDD): YYYY ($YYYY) must be between 1980 and 2029. ---");
    } elsif (0 >= $MM){
      &Die("---Error: Bad HotfixDate ($YYYYMMDD): MM ($MM) can not be less than 1.---");
    } elsif ($MM > 12){
      &Die("---Error: Bad HotfixDate ($YYYYMMDD): MM ($MM) can not be greater than 12.---");
    } elsif (0 > $DD){
      &Die("---Error: Bad HotfixDate ($YYYYMMDD): DD ($DD), can not be less than 1.---");
    } elsif ($DD > $Day[($MM - 1)]){
      &Die("---Error: Bad HotfixDate ($YYYYMMDD): DD ($DD) can not exceed " . ($Day[$MM - 1]) . " for MM/YYYY: $MM/$YYYY.---");
    }
  } else {
    &Die("---Error: Expected HotfixDate in the format YYYYMMDD: got $YYYYMMDD---");
  }
}

# Call this routine when you want to initialize the bundle files
# This routine will open the bundle files in the bundle directory, write the standard P4 keywors, variable defitions etc
# to the VBS/Bat/Txt files.
#
# Arguments: None
#
# Returns: Nothing
sub InitializeBundleFiles {

  print "--- Initializing the bundle files ---\n";
  if (! -d $BundleFilesDir) {
    make_path($BundleFilesDir);
  }

  print " $BundleFilesDir";
  # open the bundle files in the bundles directory
  open(JARSFILE, "> $BundleJarsFile") or &Die("---Error: Not able to open file $BundleJarsFile in current directory. Error is $!\n");
  open(TXTFILE, "> $BundleFilesDir\\$BundleTxtFile") or &Die("---Error: Not able to open file $BundleTxtFile in current directory. Error is $!\n");
  open(BATFILE, "> $BundleFilesDir\\$BundleBatFile") or &Die("---Error: Not able to open file $BundleBatFile in current directory. Error is $!\n");
  open(CHANGELISTFILE, "> $BundleFilesDir\\$ChangeListFile") or &Die("---Error: Not able to open file $ChangeListFile in current directory. Error is $!\n");

  TXTFILE->autoflush(1);
  BATFILE->autoflush(1);
  CHANGELISTFILE->autoflush(1);

  # Print contents into the Txt file
  print TXTFILE <<TXTEOF;

***************************************************************************************
 Manual Steps that need to be performed by Production Support for this hotfix
***************************************************************************************

1. Read through this file completely before starting.

******************************************************************************
Apply all bundled hotfixes
******************************************************************************

3. Goto the directory %yourDirectory%\\common\\dbbuild\\Db\\Hotfix\\Bundles
  run YYYYMMDDDMOHotFixBundle.bat
  (NOTE: This step calls the DBBuild file)

4. Share the bundled hotfix logs and send link to dmobds/dmorpt/dmodw alias

******************************************************************************
Manual steps after the Hotfix
******************************************************************************

TXTEOF


  # Print contents into the bat file
  print BATFILE <<BATEOF;
\@ECHO OFF
setlocal EnableDelayedExpansion

\@rem *********************************************************************************
\@rem Check for valid restart parm
\@rem *********************************************************************************
set _bundleComplete=N
if "%1" == "" (
  set _restartFound=Y
) else (
  set _restartFound=N
)

for /f usebackq %%i in (`type %0`) do (
  set _=%1
  if "%%i" == ":Problem" (
    set _bundleComplete=Y
  ) else if /i "!_:~0,3!" == "DEP" (
    if /i ":%1" == "%%i" (
      set _restartFound=Y
    )
  ) 
)

if /i "%1" == "bypassjiraverify" (
  set _restartFound=Y
)

if %_bundleComplete%==N (
  \@echo ************************************Error***************************************
  \@echo This bundle is incomplete - please check the build log
  \@echo ************************************Error***************************************
  exit /b 1
)
if "%1" == "" goto continue
if %_restartFound%==Y goto continue

\@echo ************************************Error***************************************
\@echo Restart label %1 not found
\@echo ************************************Error***************************************
exit /b 1

:continue
endlocal&set _continue=%1

set CYGWIN=nodosfilewarning

rem ---------------------------------------------
rem Set directory variables
rem ---------------------------------------------
for \%\%i in ("\%CD\%") do set hotfixdir=\%\%~fni
for \%\%i in ("\%CD\%\\..\\..\\release") do set releasedir=\%\%~fni
for \%\%i in ("\%CD\%\\..\\..\\..\\..\\..") do set BusinessSystemsdir=\%\%~fni
for \%\%i in ("\%BusinessSystemsdir\%\\..") do set BundleRootDir=\%\%~fni
set logdir=\%releasedir\%\\ApplyBundledHotfixes_LOG

if not exist "%logdir%" (
  \@echo created Directory "%logdir%"
  mkdir "%logdir%"
  if ERRORLEVEL 1 goto Problem
  )

rem ---------------------------------------------
rem verify environment
rem ---------------------------------------------
perl "%releasedir%"\\verify_environment.pl
if ERRORLEVEL 1 goto exit


rem ---------------------------------------------
rem Set username and passwords
rem ---------------------------------------------
call "%releasedir\%"\\SetPermissions.cmd

if /I "\%confirm\%"=="Q" goto exit

REM ---------------------------------------------
REM Setup variables
REM ---------------------------------------------

REM COMMON VARIABLES
set BundleDir=\%CD\%

if not "%Env%"=="" (
  set CSParseServer=ebsdevCSFS01
  set UIDrop=\\\\ebsdevweb01\\e\$\\merch_test
  set CSUIDrop=\\\\ebsdevweb01\\e\$\\clickstreamV4\\
) else (
  \@echo RUNNING IN PRODUCTION ENVIRONMENT
  set CSParseServer=DNPREEBSST01
  set UIDrop=\\\\expcpfs02\\merchpoint
  set CSUIDrop=\\\\expediaweb\\dashboard\\clickstream\\
)

set envName=NotFound
\@rem Production
if /i "%Env%"=="" (
  set envName=prod
  set ctmEnv=PRD
	set repository=http://chsxedwhdu001.idx.expedmz.com/edw
  set Infa_Repository=rep_che-etledw05
  set Infa_Host=che-etledw05
  set Infa_Port=6001
  set Infa_Service=is_infa01
  set Infa_Domain=Domain_che-etledw05
  set BO_CMS=chc-boxapp01:6400

  set prodedw_provider=db2
  set prodedw=prodedw

  set dnsqlebs02_provider=sql
  set dnsqlebs02=dnsqlebs02

  set dnsqlebs05_provider=sql
  set dnsqlebs05=dnsqlebs05

  set chexsqlebs01_provider=sql
  set chexsqlebs01=chexsqlebs01
  
  set ssas_server=chsxsasedw002

  set NTBATCHDir=\\\\DNSQLBat01\\exdprod\\job

  set eMonWebRoot=\\\\chc-webdws01\\eMon
  call set perfDir=\\\\\%\%chexsqlebs01\%\%\\perf

  set GuardianService=che-utldws03
  set GuardianFolder=d:\\guardian2
  set GuardianWebappsFolder=d:\\apache-tomcat-7.0.11\\webapps
  set GuardianUI=eMon
	
	set EZSyncServer=chs-edwctm001
	
	set ctmBatchServer=chs-edwctm001
)

\@rem Dev
if /i "%Env%"=="dev" (
  set envName=dev
  set ctmEnv=DEV
	set repository=http://cheledwhdc901.idx.expedmz.com/edw
  set Infa_Repository=rep_Development
  set Infa_Host=cheletledw001
  set Infa_Port=6001
  set Infa_Service=is_infa01
  set Infa_Domain=Domain_Development
  set BO_CMS=blwbaxi01:6400

  set prodedw_provider=db2
  set prodedw=devedw

  set dnsqlebs02_provider=sql
  set dnsqlebs02=blsqldmordv01

  set dnsqlebs05_provider=sql
  set dnsqlebs05=blsqldmordv01

  set chexsqlebs01_provider=sql
  set chexsqlebs01=blsqldmordv01
  
  set ssas_server=phelolapdev101

  set NTBATCHDir=\\\\labsqlmaster\\radprod\\job

  set eMonWebRoot=\\\\blsqldmordv01\\eMon
  call set perfDir=\\\\\%\%chexsqlebs01\%\%\\perf

  set GuardianService=
  set GuardianFolder=
  set GuardianWebappsFolder=
  set GuardianUI=

	set EZSyncServer=cheledwctm001

	set ctmBatchServer=cheledwctm001

)

\@rem Test
if /i "%Env%"=="test" (
  set envName=test
  set ctmEnv=TST
	set repository=http://cheledwhdc901.idx.expedmz.com/edw
  set Infa_Repository=rep_Test
  set Infa_Host=cheletledw011
  set Infa_Port=6001
  set Infa_Service=is_infa01
  set Infa_Domain=Domain_Test
  set BO_CMS=blarchbi01:6400

  set prodedw_provider=db2
  set prodedw=testedw

  set dnsqlebs02_provider=sql
  set dnsqlebs02=blsqldmohf02

  set dnsqlebs05_provider=sql
  set dnsqlebs05=blsqldmohf02

  set chexsqlebs01_provider=sql
  set chexsqlebs01=blsqldmohf02
  
  set ssas_server=phelolapdev102

  set NTBATCHDir=\\\\labsqlmaster\\dmohfprod\\job

  set eMonWebRoot=\\\\blsqldmortst02\\eMon
  call set perfDir=\\\\\%\%chexsqlebs01\%\%\\perf

  set GuardianService=
  set GuardianFolder=
  set GuardianWebappsFolder=
  set GuardianUI=

	set EZSyncServer=cheledwctm011

	set ctmBatchServer=cheledwctm011

)

\@rem RC
if /i "%Env%"=="rc" (
  set envName=maui
  set ctmEnv=ETE
	set repository=http://cheledwhdc901.idx.expedmz.com/edw
  set Infa_Repository=rep_Release
  set Infa_Host=cheletledw021
  set Infa_Port=6001
  set Infa_Service=is_infa01
  set Infa_Domain=Domain_Release
  set BO_CMS=chelbusedw005:6400

  set prodedw_provider=db2
  set prodedw=rcedw

  set dnsqlebs02_provider=sql
  set dnsqlebs02=chelsqldw01

  set dnsqlebs05_provider=sql
  set dnsqlebs05=chelsqldw01

  set chexsqlebs01_provider=sql
  set chexsqlebs01=chelsqldw01
  
  set ssas_server=phelolapdev103

  set NTBATCHDir=\\\\labsqlmaster\\dw1hprod\\job

  set eMonWebRoot=\\\\chelsqldw01\\eMon
  call set perfDir=\\\\\%\%chexsqlebs01\%\%\\perf
  
  set GuardianService=chelgwsedw003
  set GuardianFolder=d:\\guardian2
  set GuardianWebappsFolder=d:\\apache-tomcat-7.0.11\\webapps
  set GuardianUI=chelgwsedw003

	set EZSyncServer=cheiedwctm021

	set ctmBatchServer=cheiedwctm021
)

\@rem Milan
if /i "%Env%"=="mln" (
  set envName=milan
  set ctmEnv=MILAN
	set repository=http://cheledwhdc901.idx.expedmz.com/edw
  set Infa_Repository=rep_ReleaseMilan
  set Infa_Host=cheletledw201
  set Infa_Port=6001
  set Infa_Service=is_infa01
  set Infa_Domain=Domain_ReleaseMilan
  set BO_CMS=chelbusedw201:6400

  set prodedw_provider=db2
  set prodedw=mlnedw

  set dnsqlebs02_provider=sql
  set dnsqlebs02=CHELSQLEDW201

  set dnsqlebs05_provider=sql
  set dnsqlebs05=CHELSQLEDW201

  set chexsqlebs01_provider=sql
  set chexsqlebs01=CHELSQLEDW201
  
  set ssas_server=phelolapdev104

  set NTBATCHDir=\\\\labsqlmaster\\mlnprod\\job

  set eMonWebRoot=\\\\chelsqledw201\\eMon
  call set perfDir=\\\\\%\%chexsqlebs01\%\%\\perf

  set GuardianService=chelgwsedw201
  set GuardianFolder=d:\\guardian\\newenv
  set GuardianWebappsFolder=d:\\apache-tomcat-7.0.11\\webapps
  set GuardianUI=chelgwsedw201

	set EZSyncServer=chesedwctm201

	set ctmBatchServer=chesedwctm201	
)

\@rem PPE
if /i "%Env%"=="ppe" (
  set envName=ppe
  set ctmEnv=
	set repository=
  set Infa_Repository=rep_dnetledw01
  set Infa_Host=dnetledw01
  set Infa_Port=6001
  set Infa_Service=is_infa01
  set Infa_Domain=Domain_dnetledw01
  set BO_CMS=\@ppecluster

  set prodedw_provider=db2
  set prodedw=ppeedw

  set dnsqlebs02_provider=sql
  set dnsqlebs02=blsqlds01

  set dnsqlebs05_provider=sql
  set dnsqlebs05=blsqlds01

  set chexsqlebs01_provider=sql
  set chexsqlebs01=blsqlds01

  \@rem set NTBATCHDir=\\\\labsqlmaster\\radprod\\job
  set NTBATCHDir=\\\\labsqlmaster\\tstprod\\job

  set eMonWebRoot=\\\\blsqlds01\\eMon
  call set perfDir=\\\\\%\%chexsqlebs01\%\%\\perf

  set GuardianService=
  set GuardianFolder=
  set GuardianWebappsFolder=
  set GuardianUI=
  set EZSyncServer=

)

\@echo ---------------------------------------------
\@echo Variables
\@echo ---------------------------------------------


\@echo BO_CMS=\%BO_CMS\%
\@echo BO_User=\%BO_User\%
\@echo BundleDir=\%BundleDir\%
\@echo BundleRootdir=\%BundleRootdir\%
\@echo BusinessSystemsdir=\%BusinessSystemsdir\%
\@echo CSParseServer=\%CSParseServer\%
\@echo CSUIDrop=\%CSUIDrop\%
\@echo DB2_User=\%DB2_User\%
\@echo ENV=\%ENV\%
\@echo EZSyncServer=\%EZSyncServer\%
\@echo GuardianFolder=\%GuardianFolder\%
\@echo GuardianUI=\%GuardianUI\%
\@echo GuardianWebappsFolder=\%GuardianWebappsFolder\%
\@echo Infa_Domain=\%Infa_Domain\%
\@echo Infa_Host=\%Infa_Host\%
\@echo Infa_Port=\%Infa_Port\%
\@echo Infa_Repository=\%Infa_Repository\%
\@echo Infa_Service=\%Infa_Service\%
\@echo Infa_User=\%Infa_User\%
\@echo NTBATCHDir=\%NTBATCHDir\%
\@echo UIDrop=\%UIDrop\%
\@echo chexsqlebs01=\%chexsqlebs01\%
\@echo ctmEnv=\%ctmEnv\%
\@echo dnsqlebs02=\%dnsqlebs02\%
\@echo dnsqlebs05=\%dnsqlebs05\%
\@echo eMonWebRoot=\%eMonWebRoot\%
\@echo envName=\%envName\%
\@echo hotfixdir=\%hotfixdir\%
\@echo logdir=\%logdir\%
\@echo perfDir=\%perfDir\%
\@echo prodedw=\%prodedw\%
\@echo pythoncmd=\%pythoncmd\%
\@echo releasedir=\%releasedir\%
\@echo repository=\%repository\%
\@echo SQLUser=\%SQLUser\%

rem ---------------------------------------------
rem Update informatica control files
rem ---------------------------------------------
if /i "\%env\%"=="dev" (
  for \%\%i in ("\%BusinessSystemsDir\%\\Informatica\\db\\release\\*.xml") do perl -p -i.bak -w -e "s/CHECKIN_AFTER_IMPORT\\=\\".*?\\"/CHECKIN_AFTER_IMPORT\\=\\"YES\\"/gi" "\%\%i"
  for \%\%i in ("\%BusinessSystemsDir\%\\Informatica\\db\\release\\*.xml") do perl -p -i.bak -w -e "s/CHECKIN_COMMENTS\\=\\".*?\\"/CHECKIN_COMMENTS\\=\\"Dev Unit Test by \%Infa_User\%\\"/gi" "\%\%i"
)

if /i NOT "\%env\%"=="dev" (
  for \%\%i in ("\%BusinessSystemsDir\%\\Informatica\\db\\release\\*.xml") do perl -p -i.bak -w -e "s/CHECKIN_AFTER_IMPORT\\=\\".*?\\"/CHECKIN_AFTER_IMPORT\\=\\"NO\\"/gi" "\%\%i"
  for \%\%i in ("\%BusinessSystemsDir\%\\Informatica\\db\\release\\*.xml") do perl -p -i.bak -w -e "s/CHECKIN_COMMENTS\\=\\".*?\\"/CHECKIN_COMMENTS\\=\\"\\"/gi" "\%\%i"
)

for \%\%i in ("\%BusinessSystemsDir\%\\Informatica\\db\\release\\*.xml") do perl -p -i.bak -w -e "s/TARGETREPOSITORYNAME\\=\\".*?\\"/TARGETREPOSITORYNAME\\=\\"\%Infa_Repository\%\\"/gi" "\%\%i"

if not "%_continue%" == "" (
  goto %_continue%
)

BATEOF

  # Check to see that these are non zero files after initialization
  (-s "$BundleFilesDir\\$BundleTxtFile") or &Die("--Error in Initialization. File size of $BundleFilesDir\\$BundleTxtFile is zero.");
  (-s "$BundleFilesDir\\$BundleBatFile") or &Die("--Error in Initialization. File size of $BundleFilesDir\\$BundleBatFile is zero.");

  # print success
  print "--- Successfully Initialized the bundle files ---\n";
}

sub GenerateRandomString {
  my ($length_of_randomstring)=shift;# the length of the random string to generate

  my @chars=('a'..'z','A'..'Z','0'..'9','_');
  my $random_string;

  # rand @chars will generate a random number between 0 and scalar @chars
  foreach (1..$length_of_randomstring) {
    $random_string.=$chars[rand @chars];
  }
  return $random_string;
}

sub IntegrateFiles {
  open(ClientInteglocationFile, "< ClientIntegView\.txt");
  undef $/;
  my $ClientInteglocations = <ClientInteglocationFile>;
  close(ClientInteglocationFile);

  open(P4Client, ">> P4client.ini");
  print  P4Client  "$ClientInteglocations";
  close (P4Client);

  &Debug("calling P4 client in order to create P4client.ini");
  $Command = "P4 client -i < P4client.ini 2>&1";
  system($Command);

  open(FilesToIntegrate, "< Integration\.txt");
  print " Integration\.txt Opened \n";

  undef $/;
  my $IntegFileContents = <FilesToIntegrate>;
  close(FilesToIntegrate);
  my(@FilesToIntegrate) = split("\n", $IntegFileContents);

  foreach(@FilesToIntegrate) {
    print "Integrating $_ \n";
    $Command = "p4 integ -i -v -d $_";
    system($Command);
    $Command = "p4 resolve -at ";
    system($Command);
  }


  $Command = "p4 submit";
  system($Command);
}

sub CheckModuleVersion {
  my ($module)    = shift;
  my ($min_version)  = shift;
  my $version    = eval("$module->VERSION");

  if ( $version < $min_version ) {
    &Die("This script requires you have version $min_version or later of " .
      "the $module module. Please upgrade module or reinstall the " .
      "latest version of perl.");
  }
}

sub GetDBBuildFiles {
  my $p4_path;
  my $cmd;
  my $file;
  my $from;
  my $to;
  my $return;
  my $objecttype;

  local ( $/ ) = "\n";

  foreach $objecttype ( sort keys %DeployObjects ) {
    $p4_path = "//depot/dmo/Common/DBBuild/main/$objecttype.txt";
    $cmd = "p4 print $p4_path";

    open ( CMD, "$cmd 2>&1 |" ) || &Die("\n\nCouldn't run command: $cmd\n\nERROR: $!\n\n\n");

    while ( <CMD> ) {
      # process line from file
      chomp;
      $file = $_;
      if ( $_ =~ /no such file\(s\)/i ) {
        &Die("Couldn't run command: $cmd\n\nERROR: $file\n\n\n");
      }
      next if ( $file =~ /^$p4_path/i );
      $file =~ s/#.*$//;
      next if ( $file =~ /^\s*$/ );
      $file =~ s/\\/\//g;
      next if ( $file =~ /\.vbs$/ );

      # Create perforce mapping
      $from = "//depot/dmo/$file";
      $from =~ s/\/db\//\/main\/db\//i;
      $to = "//$client/BusinessSystems/$file";
      $objects{$from} = $to;
      $return .= "  $from  $to\n";

      # Create vbs file
      &Die("\nERROR: Files not in the common branch are currently not supported:\n  $file\n\n") if ( $file !~ /^common/ );
    }

    close ( CMD );

    $file = "BusinessSystems\\Common\\DBBuild\\db\\hotfix\\$objecttype.vbs";
    open ( OBJECT_VBSFILE, ">$file" ) || &Die("Couldn't open file, $file, for writing: $!\n");

    print OBJECT_VBSFILE "\ndim gnBuildType_tmp\n";
    print OBJECT_VBSFILE "gnBuildType = gcnBUILD_TYPE_SETUP\n\n";

    #print OBJECT_VBSFILE "call CreateLoginsAndUsers\n";
    print OBJECT_VBSFILE "call VerifyBuildTablesandSprocs\n";
    print OBJECT_VBSFILE "call DBBuildStart\n";
    print OBJECT_VBSFILE "call CreateDatatypes\n";
    print OBJECT_VBSFILE "call CreateTables\n";
    print OBJECT_VBSFILE "call CreatePrimaryKeys\n";
    print OBJECT_VBSFILE "call CreateAlternateKeys\n";
    print OBJECT_VBSFILE "call CreateIndexes\n";
    print OBJECT_VBSFILE "call CreateAllOptionalItems\n";
    print OBJECT_VBSFILE "call CreateTriggers\n";
    print OBJECT_VBSFILE "call CreateFunctions\n";
    print OBJECT_VBSFILE "call CreateViews\n";
    print OBJECT_VBSFILE "call CreateStoredProcedures\n";
    print OBJECT_VBSFILE "call CreateSystemMessages\n";
    print OBJECT_VBSFILE "call CreateData\n";
    print OBJECT_VBSFILE "call CreateForeignKeys\n";
    print OBJECT_VBSFILE "'call ApplyGrants\n";
    print OBJECT_VBSFILE "call BuildSettingsSet\n";
    print OBJECT_VBSFILE "call DBBuildFinish\n\n";

    print OBJECT_VBSFILE "gnBuildType = gnBuildType_tmp\n\n";

    close ( OBJECT_VBSFILE );
  }

  return $return;
}

sub progress_bar {
  my ( $got, $total ) = @_;

  my $width = 25;
  my $char = '=';
  my $num_width = length $total;

  sprintf "|%-${width}s| Got %${num_width}s bytes of %s (%.2f%%)\r"
    , $char x (($width-1)*$got/$total). '>'
    , $got
    , $total
    , 100*$got/+$total;
}

sub CheckBOUniverse {
  my ($_BundleVBSFiles) = shift;

  print "Checking BO Universe deployments...\n";
  foreach my $_BundleVBSFile (@{$_BundleVBSFiles}) {
    my $status = &checkIncludingUniverse("$BundleFilesDir\\$_BundleVBSFile");
    if (&useBoedwbiarForUniverse($status)) {
      if (defined $opt_oldbounv) { 
        print <<EOF;
===========================================================================
=               *** WARNING ***               =
=                                     =
= You still use BOEDWBIAR to deploy universes. This is *NOT* recommended. =
= Please use BOEDWUNV, which can set the connection string automatically, =
= and no manual steps are needed. Using BOEDWUNV will be enforced in the =
= future.                                 =
=                                     =
= Refer this wiki page:                          =
=  http://confluence/display/EDWDev/BO+Universe+Deployment+Module    =
===========================================================================
EOF
      } else {
        my $msg =<<EOF;
===========================================================================
= Using BOEDWBIAR to deploy universes is deprecated. Please use BOEDWUNV. =
=                                     =
= Refer this wiki page:                          =
=  http://confluence/display/EDWDev/BO+Universe+Deployment+Module    =
===========================================================================
EOF
        &Die($msg);
      }
    }
  }
  
  return;
}

END {
  my $errorcode = $?;
  $Command = "P4 client -d $client";
  &Debug(system($Command));
  exit ($errorcode);
}

