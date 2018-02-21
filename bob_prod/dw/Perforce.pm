package Perforce;

use strict;
use Carp;        # give us the confess() function which prints a stack trace when exiting abnormally
use FileHandle;  # Allow us to tweak attributes of STDERR and STDOUT
use File::Basename;  # Let's us tweak directory and unc paths and file names
use Cwd 'abs_path';  # Gets the absolute path of any directory you pass.

require Exporter;

@Perforce::ISA = qw(Exporter);
@Perforce::EXPORT = qw(
   AbsPath
   BaseFromRaid
   CallSystem
   Debug
   Die
   ErrorLog
   IsEDWRaid
   IsLDWRaid
   LinesFromFile
   P4FileExists
   RaidFileFromNumber
);

STDOUT->autoflush(1); # Flush the stdout immediately
STDERR->autoflush(1); # Flush the stderr immediately

# These variables will be available to any calling programs and are set below.
local($Perforce::Author);
local($Perforce::Change);
local($Perforce::Date);
local($Perforce::DevAccessUserArgs);
local($Perforce::EDWBase);
local($Perforce::LDWBase);
local($Perforce::Revision);
local($Perforce::Source);
local(@Perforce::DBDirectories);
local(@Perforce::P4Port);

# Accepts an NT command, then prints the command, and runs it.
# If it was a robocopy command, search for error conditions, and print 'em
# Also attempts to search the $Command which includes osql or bcp for ">File.txt" and will print File.txt
# If ReturnValue = 0, return Success (1)
# If ReturnValue != 0, return Failure (0)
#
# Argument1: $Command   - String containing the NT Command to run.
sub CallSystem {

    my($Command) = @_;
    my($RetVal);
    my($OutputFile);   # Slurped from the end of the $Command if it ends in > FileName
                       # Note this is only set if the $OutputFile should be printed.

    # Default to not printing.
    undef($OutputFile);

    # Look for the string " > filename.txt 2>&1 " at the end of the command.
    # if you find it, save the OutputFile.
    if ($Command =~ /(>) ([^"'>]+) *(2>&1)* *$/i) {
       $OutputFile = $2;
       &Debug("Perforce::CallSystem: Output File Name: $OutputFile");
    } else {
       undef($OutputFile);
       &Debug("Perforce::CallSystem: found no output file at the end of this osql or bcp command");
    }

    &Debug("Perforce::CallSystem: $Command" );

    $RetVal = system($Command);

    # Divide the return value from system by 256 to get the real exit value.
    # NOTE: RetVal overflows the int at about 250, so never return
    # An int higher than 250 with this technique
    $RetVal = $RetVal / 256;
    &Debug("Perforce::CallSystem: Return Value: $RetVal" );

    # Check for RoboCopy specific errors
    if ($Command =~ /robocopy/i) {
        # Robocopy

        if ($RetVal & 16) {
            &ErrorLog("Perforce::CallSystem: Robocopy encountered a fatal error: $RetVal\n");
        } elsif ($RetVal & 8) {
            &ErrorLog("Perforce::CallSystem: Not all files successfully copied: $RetVal\n");
        } elsif ($RetVal & 4) {
            &ErrorLog("Perforce::CallSystem: Robocopy detected mismatched Files or Dirs: $RetVal\n");
        } elsif ($RetVal & 2) {
            # This is not a fatal error
            $RetVal = 0;
            &Debug("Perforce::CallSystem: Robocopy detected extra files $RetVal\n");
        } elsif ($RetVal & 1) {
            # This is not a fatal error
            $RetVal = 0;
            &Debug("Perforce::CallSystem: Robocopy found new files to copy: $RetVal\n");
        } else {
           $RetVal = 0;
        }
    } elsif (defined($OutputFile)) {
       # If the output was redirected to a file, print out the text in the file name if there was an error.
       if ($RetVal > 0) {
          &ErrorLog("Perforce::CallSystem Command Failed: $Command\nText in file: $OutputFile:\n". `type $OutputFile`) ;
       }
   } elsif ($Command =~ /unzip .*-P/i) {
      # Unzip.exe return error code 82 when you pass a bad password.
      if ($RetVal == 82) {
         &ErrorLog("Perforce::CallSystem: unzip.exe: Bad Password while extracting file with command: $Command\n") ;
      } elsif ($RetVal == 11) {
         &ErrorLog("Perforce::CallSystem: unzip.exe: Unable to find all files in Archive with command: $Command\n") ;
      } elsif ($RetVal != 0) {
         &ErrorLog("Perforce::CallSystem: unzip.exe Command Failed: $Command\n") ;
      }
   } else {
      # Not Robocopy, nor isql with exit()
      if ($RetVal > 0) {
         &ErrorLog("Perforce::CallSystem: Command Failed: $Command\n") ;
      }
   }

   #Return 1 (Success) if $RetVal == 0, 0 otherwise
   return(($RetVal == 0) ? 1 : 0);
}

# Print messages if the script was called with perl -w
#
# Argument 1   $Message - The message you'd like printed if you're in debug mode.

sub Debug {
   my($Message) = @_;

   if ($^W) {
      print "Debug: $Message\n";
   }
}

# Print message and exits with a stack trace from carp::confess
#
# Argument 1   $Message - The message you'd like printed before the program exits

sub Die {
   my($Message) = @_;

   confess("$Message\n");
}

# Print error messages without dying
#
# Argument 1   $Message - The message you'd like printed.

sub ErrorLog {
   my($Message) = @_;

   print "Perforce::ErrorLog: $Message\n";
}

# Checks to see if a file exists in perforce
#
# Argument 1   $file - The file to check for the existance of.
sub P4FileExists () {
   my $command;
   my $file;
   my $output;

   ( $file ) = @_;

   $command = "p4 files $file";

   open ( FILE, "$command 2>&1 |" ) or &Die("Couldn't run command:  $command\n$!");
   {
      local( $/ );
      $output = <FILE>;
   }
   close ( FILE );

   if ( $output =~ /no such file/ ) {
      return undef;
   } else {
      return 1;
   }
}

# Check to see if raid.txt file exists in either dmo or edw branch of perforce.
#
# Argument 1   $raid - The number of a raid.
sub IsValidRaid () {
   my $raid;

   ( $raid ) = @_;

   if ( &IsEDWRaid ( $raid ) or &IsLDWRaid ( $raid ) ) {
      return 1;
   } else {
      return undef;
   }
}

# Check to see if raid.txt file exists in edw branch of perforce.
#
# Argument 1   $raid - The number of a raid.
sub IsEDWRaid () {
   my $raid;

   ( $raid ) = @_;

   return &P4FileExists ( &RaidFileFromNumber ( $raid, 'edw' ) );
}

# Check to see if raid.txt file exists in dmo branch of perforce.
#
# Argument 1   $raid - The number of a raid.
sub IsLDWRaid () {
   my $raid;

   ( $raid ) = @_;

   return &P4FileExists ( &RaidFileFromNumber ( $raid, 'ldw' ) );
}


# Derive the full path/name of a raid.txt file from the raid number and branch name.
#
# Argument 1   $raid - The number of a raid.
# Argument 2   $branch - The branch to create the filename for.
sub RaidFileFromNumber () {
   my $raid;
   my $branch;
   my $file;

   ( $raid, $branch ) = @_;

   &Die ("Raid number specified is not numeric:  $raid\n") if ( $raid =~ /[^\d]/ );

   if ( $branch =~ /^edw$/i ) {
      $file = $Perforce::EDWBase . "/Common/DBBuild/dev/db/HotFix/Bundles/RaidFiles/raid$raid.txt";
   } elsif ( $branch =~ /^(?:ldw|dmo)$/i ) {
      $file = $Perforce::LDWBase . "/Common/DBBuild/dev/db/HotFix/Bundles/RaidFiles/raid$raid.txt";
   } else {
      &Die ("Invalid branch specified:  $branch\n");
   }

   return $file;
}

# Find the the base pathname for the perforce branch that a raid belongs to.
#
# Argument 1   $raid - The number of a raid.
sub BaseFromRaid () {
   my $raid;

   ( $raid ) = @_;

   if ( &IsEDWRaid ( $raid ) ) {
      return $Perforce::EDWBase;
   } elsif ( &IsLDWRaid ( $raid ) ) {
      return $Perforce::LDWBase;
   } else {
      &Die ( "Raid does not exist in perforce:  $raid\n" );
   }
}

# Call the Cwd::abs_path function on Arg 1 which can be either
# a file or a directory (relative or absolute)
#
# Note that we cannot call abs_path directory because older
# version don't work with file names, only directory names.
#
# Argument 1   $Path - The absolute or relative path to a file or directory.
#
# Returns the absolute path to the file requested or it dies

sub AbsPath {
   my($Path) = shift;
   my($AbsolutePath) = "";
   my($PathType) = "(unable to determine)";

   if (not defined $Path or $Path eq "") {
      &Die("Perforce::AbsPath: Unable to retrieve valid value for Argument 1: \$Path");
   }

   &Debug("Perforce::AbsPath: \$Path = $Path");

   # File::Basename::dirname returns the directory (without the filename) when passed a path
   # File::Basename::basename returns the name of the file (without the directory info) when passed a path
   # Cwd::abs_path returns the absolute path name of the directory you pass in.
   #               Note that later releases work when passed a directory or file, older version require a directory
   #               which is why we created this function.
   if ( -f "$Path") {
      $AbsolutePath = abs_path(dirname($Path)) . "\\" . basename($Path);
      $PathType = "file";
   } elsif (-d "$Path") {

      $AbsolutePath = abs_path($Path);
      $PathType = "directory";
   } else {
      &Die("Perforce::AbsPath: Argument 1 is not a file or directory: $Path");
   }

   # Change all the Unix / to DOS \
   $AbsolutePath =~ tr#/#\\#;

   &Debug("Perforce::AbsPath: Absolute path for $PathType: $AbsolutePath");

   return $AbsolutePath
}

# Reads the passed in file and returns an array containing all non-blank, non-comment lines.
#
# Arg 1 FileName Text file which must exist
#
# Returns: Array of lines from file which contain non-space characters and which do not start with # (comment)
sub LinesFromFile {
   my($FileName) = shift;
   my(@Lines);

   if (not -f $FileName) {
      &Die("Perforce::LinesFromFile: Unable to find input file: $FileName: $!");
   } else {
      &Debug("Perforce::LinesFromFile: Opening input file: $FileName and looping over non-blank, non-comment lines");

      open (INPUTFILE, "$FileName")
         or &Die("Perforce::LinesFromFile: Unable to open input file: $FileName : $!");

      while (<INPUTFILE>) {
         chomp();
         next if s/^#//;     # Skip comments
         next if s/^\s*$//;  # Skip blank lines.
         s/\s+$//;           # Strip off trailing spaces and tabs.

         &Debug("Perforce::LinesFromFile: $FileName: Line $.: $_");

         push(@Lines, $_);
      }

      close(INPUTFILE) or &Die("Perforce::LinesFromFile: Unable to close input file: $FileName : $!");
   }

   return (@Lines);
}


BEGIN {
   # Turn on Debugging if you got -d as any of the arguments
   if (grep {/^-d$/} @ARGV) {
      $^W = 1;
      &Debug("Perforce.pm: Found '-d' in argument list, turning on debugging (and removing -d from argument list)");
      @ARGV = grep {not /^-d$/} @ARGV;
      &Debug("New Arg List: @ARGV");
   }

   # Source Depot Keywords
   $Perforce::Author   = '$Author: adillow $';
   $Perforce::Change   = '$Change: 108528 $';
   $Perforce::Date     = '$Date: 2009/09/23 $';
   $Perforce::Source   = '$Source$';
   $Perforce::Revision = '$Revision: #4 $';
   $Perforce::EDWBase  = '//depot/edw';
   $Perforce::LDWBase  = '//depot/dmo';

   # Set these
   $Perforce::DevAccessUserArgs = " -U DevAccess -P waterf\@lls";

   # List of Directories required by DBBuild.vbs, other directories are permitted, but these are required.
   @Perforce::DBDirectories = qw(
                                    dat
                                    func
                                    global
                                    Hotfix
                                    patch
                                    release
                                    sp
                                    view
                                    tbl
                                    tbl\\constraint
                                    tbl\\constraint\\check
                                    tbl\\constraint\\fk
                                    tbl\\constraint\\pk
                                    tbl\\constraint\\unique
                                    tbl\\index
                                    tbl\\options
                                    tbl\\trg
                                    tbl\\udt
   );

   # Source Depot port which should be used by all P4 commands
   if ( ! defined $ENV{'p4port'} ) {
      $Perforce::P4Port = "Perforce:1985";
   } else {
      $Perforce::P4Port = $ENV{'p4port'};
   }

   &Debug("Perforce.pm: $Perforce::Author");
   &Debug("Perforce.pm: $Perforce::Change");
   &Debug("Perforce.pm: $Perforce::Date");
   &Debug("Perforce.pm: $Perforce::Source");
   &Debug("Perforce.pm: $Perforce::Revision");
   &Debug("Perforce.pm: DevAccessUserArgs: $Perforce::DevAccessUserArgs");
   &Debug("Perforce.pm: P4Port:            $Perforce::P4Port");
}

1;  # Modules must return a true value
