use strict;
use Getopt::Long;

use File::Basename;    
use lib dirname(__FILE__);

use BundleBuild::Build qw(getBuildScriptOptions);

my ($opt_LabelName);
my ($opt_ChangeListFile);
my ($opt_ClientName);
my ($opt_ClientRoot);
my ($opt_branch);
my ($opt_IntegrateTo);
my ($opt_Raids);

&GetOptions(
     "LabelName:s",        \$opt_LabelName
   , "ChangeListFile:s",   \$opt_ChangeListFile
   , "ClientName:s",       \$opt_ClientName
   , "ClientRoot:s",       \$opt_ClientRoot
   , "Branch:s",           \$opt_branch
   , "IntegrateTo:s",      \$opt_IntegrateTo
   , "Raids:s",            \$opt_Raids
);


my($Command);
my(@FilesToTag);
my(@ChangeLists);
my($LabelDefFile);
my($ChangeListNumber);
my(@ChangeNumber);
my($base);
my($file);
my($rev);
my($file_nobranch);
my($file_integ);
my($timestamp);
my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);

$timestamp = sprintf "%4d/%02d/%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec;

open(ClientIni, "P4client.ini")
   or &Die("Unable to open the P4client.ini file created earlier in this script: $!");

my(@P4ClientLines) = <ClientIni>;

close(ClientIni) or &Die("Unable to close the P4client.ini file after reading: $!");

open(ClientIni, ">P4client.ini")
   or &Die("Unable to open the P4client.ini file for over-writing: $!");

# Print all the info from the original.
for (@P4ClientLines){
   chomp();
   print ClientIni "$_\n"; }

$opt_ClientName = "$opt_ClientName/BusinessSystems";
$LabelDefFile = "Label_$opt_LabelName\.txt";
open(LabelDef, "> $LabelDefFile") ;   #Create Label Header


print LabelDef <<LabelDefEOF;
         # A Perforce Label Specification.
         #
         #  Label:       The label name.
         #  Update:      The date this specification was last modified.
         #  Access:      The date of the last 'labelsync' on this label.
         #  Owner:       The user who created this label.
         #  Description: A short description of the label (optional).
         #  Options:     Label update options: locked or unlocked.
         #  View:        Lines to select depot files for the label.
         #
         # Use 'p4 help label' to see more about label views.

Label:   $opt_LabelName

Update:  $timestamp

Access:  $timestamp

Owner:

Description:
   Created by CreateLabelDef.pl.

Options: unlocked

View:
LabelDefEOF

if ( defined $opt_Raids ) {
   my %bs_opts = &getBuildScriptOptions(undef);
   print LabelDef "   $bs_opts{path}\n";
   push ( @FilesToTag, $bs_opts{path} );

   foreach my $raid ( split /:/, $opt_Raids ) {
      print LabelDef "   $opt_ClientRoot/Common/DBBuild/$opt_branch/db/HotFix/Bundles/RaidFiles/raid$raid.txt\n";
      push ( @FilesToTag, "$opt_ClientRoot/Common/DBBuild/$opt_branch/db/HotFix/Bundles/RaidFiles/raid$raid.txt" );
   }
} else {
   print LabelDef "   $opt_ClientRoot/common/DBBuild/$opt_branch/db/...\n";
   push ( @FilesToTag, "$opt_ClientRoot/Common/DBBuild/$opt_branch/db/..." );
}

if ( $opt_ClientRoot =~ /edw/i ) {
   print LabelDef "   $opt_ClientRoot/Informatica/$opt_branch/db/release/...\n";
   push ( @FilesToTag, "$opt_ClientRoot/Informatica/$opt_branch/db/release/..." );
}

open(IntegFiles, "> Integration\.txt") ; #create file to use for integration later if needed.
open(ClientInteglocationFile, "> ClientIntegView\.txt"); #create file to use to add entries for integrated files to client view.

# Read all changelists related to this raid.
open ( CHANGELISTFILE, $opt_ChangeListFile )
   or die "Couldn't open file, $opt_ChangeListFile, for reading:  $!\n";

print "Reading changelists from $opt_ChangeListFile\n" ;

while ( <CHANGELISTFILE> ) {
   next if ( /^\s*$/ );
   if ( /^\s*(\d+)\s*$/ ) {
      push @ChangeNumber, $1;
   } else {
      die "Error malformed changelist:  $_\n";
   }
}

close ( CHANGELISTFILE );

 #file defs to the label file
foreach $ChangeListNumber ( @ChangeNumber ) {
   print "Processing changelist:  $ChangeListNumber\n";

   $Command = "p4 describe -s $ChangeListNumber > ChangeListFiles.txt";
   system ( $Command );

   open ( ChangeListFiles, "ChangeListFiles.txt" )
      or die "Couldn't open file, ChangeListFiles.txt, for reading:  $!\n";
   while ( <ChangeListFiles> ) {
      if ( /^\.\.\.\s+(\/\/[^\/]+\/[^\/]+\/)(.*)(#\d+)/ ) {
         $base          = $1;
         $file          = $2;
         $rev           = $3;

         $file_nobranch = $file;
         $file_integ    = $file;

         $file_nobranch =~ s/\/$opt_branch\//\//i;
         $file_integ    =~ s/\/$opt_branch\//\/$opt_IntegrateTo\//i;

         push ( @FilesToTag, &add_quotes ( "$base$file$rev" ) );

         print LabelDef "   " . &add_quotes ( "$base$file" ) . "$rev\n";
         print ClientIni "   " . &add_quotes ( "$base$file" ) . "   " . &add_quotes ( "//$opt_ClientName/$file_nobranch" ) . "\n";
         if ( $file !~ /\/hotfix\//i ) {
            print IntegFiles " " . &add_quotes ( "$base$file" ) . "$rev " . &add_quotes ( "$base$file_integ" ) . "\n";
            print ClientInteglocationFile " " . &add_quotes ( "$base$file_integ" ) . " " . &add_quotes ( "//$opt_ClientName/$file_integ" ) . "\n";
         }
      }
   }
   close(ChangeListFiles);
}
close(LabelDef);
close(ClientIni);

#Delete the label if it already exists
$Command = " p4 label \-d $opt_LabelName ";
system($Command);

#create label
$Command = " p4 label \-i < $LabelDefFile ";
system($Command);

#tag files in the label def.
foreach(@FilesToTag){
   my($filetotag) = $_;
   if (not $filetotag eq "") {
      $Command = " p4 tag \-l $opt_LabelName $filetotag";
      system($Command);
   }
}


sub add_quotes {
   my $path = shift;

   $path = '"' . $path . '"' if ( $path =~ /\s+/ );

   return $path;
}
