

use strict;

my %flags;
my @options;
my $usage;
my @raids;
my $raid;
my $command;
my $line;
my $section;
my %changelists;
my $cl;
my $file;
my $rev;
my $type;
my %change_details;
my %raid_details;
my $raidfile;

$usage =
   "\ndep [raid#1] [raid#2] ... [raid#n]\n\n" .
   "   raid#x   These are the raid numbers that will be checked for dependancies\n\n";

&ProcessCmdLine ( -1 );

@raids = @options;

RAID_FILE: foreach $raid ( sort { $a <=> $b } @raids ) {
   $raidfile = &raidfile_name ( 'dmo', $raid );

   $raidfile = &raidfile_name ( 'edw', $raid ) if ( &DoesP4FileExist ( $raidfile ) == 0 );

   $command = "p4 print $raidfile";

   open ( RAID, "$command 2>&1 |" ) or die "Couldn't run command $command:  $!\n";

   $line = 0;
   while ( <RAID> ) {
      $line++;
      chomp;

      if ( /no such file/ ) {
         print "No raid file exists for raid $raid.\n";
         next RAID_FILE;
      }

      # Determine what section we are in
      if ( /^\s*\[.*\]\s*$/ ) {
         undef ( $section );
         if ( /^\s*\[Section:\s*(\w+)\s*\]\s*$/i ) {
            $section = $1;
         }
         next;
      }

      # Find all Changelists
      if ( $section =~ /^Changelists$/i ) {
         s/\s*#.*$//;
         next if ( /^\s*$/ );
         if ( /^\s*(\d+)\s*$/ ) {
            $changelists{$raid}{$1} = 1;
         } else {
            die "ERROR:  Malformed line in raid $raid line $line:\n   $_\n";
         }
      }
   }

   close ( RAID );
}

foreach $raid ( sort { $a <=> $b } keys %changelists ) {
   print "Processing changelists for raid:  $raid\n";
   foreach $cl ( sort { $a <=> $b } keys %{ $changelists{$raid} } ) {
      print "   Changelist $cl...\n";
      $command = "p4 describe -s $cl";

      open ( CL, "$command |" ) or die "Couldn't run command $command:  $!\n";

      while ( <CL> ) {
         if ( /^\.\.\. (.*)#(\d+)\s+(\w+)\s*$/ ) {
            $file = $1;
            $rev  = $2;
            $type = $3;

            $change_details{$file}{$cl}{"rev"}           = $rev;
            $change_details{$file}{$cl}{"type"}          = $type;
            $change_details{$file}{$cl}{"raid"}{$raid}   = 1;
            $raid_details{$file}{$raid}                  = 1;
         }
      }

      close ( CL );
   }
}

print "\n\nOutputting results...\n\n\n";

foreach $file ( sort { $a <=> $b } keys %raid_details ) {
   # Only display details for files that are changed by more than one raid.
   if ( keys ( %{ $raid_details{$file} } ) > 1 ) {
      print "\n$file\n";
      foreach $cl ( sort { $a <=> $b } keys %{ $change_details{$file} } ) {
         foreach $raid ( sort { $a <=> $b } keys %{ $change_details{$file}{$cl}{"raid"} } ) {
            print "   Raid $raid - changelist $cl ( rev " . $change_details{$file}{$cl}{"rev"} . ").\n";
         }
      }
   }
}



#######################################################################################
# Subroutines
#######################################################################################

sub raidfile_name {
   my ( $depot, $raidnumber ) = @_;

   return "//depot/$depot/Common/DBBuild/DEV/db/hotfix/bundles/RaidFiles/Raid$raidnumber.txt";
}

sub DoesP4FileExist {
   my ( $p4, $output );
   ( $p4 ) = @_;

   $command = "p4 files $p4";
   open ( P4EXISTS, "$command 2>&1 |" ) or die "Couldn't run command $command:  $!\n";
   {
      local( $/ );
      $output = <P4EXISTS>;
   }
   close ( P4EXISTS );
   
   return ( $output =~ /no such file/ ? 0 : 1 );
}

sub ProcessCmdLine {
   my ( $i, $flag, $args );

   ( $args ) = @_;

   foreach $flag ( keys %flags ) {
      if ( $flags{$flag} !~ /^(?:no )?param$/i ) {
         die "Invalid flag configuration for $flag ( $flags{$flag} ).  Please use \"param\" or \"no param\".\n";
      }
   }

   for ( $i = 0; $i <= $#ARGV; $i++ ) {
      if ( $ARGV[$i] =~ /^\-.*$/ ) {
         if ( defined $flags{$ARGV[$i]} ) {
            if ( $flags{$ARGV[$i]} =~ /^no param$/i ) {
               $flags{$ARGV[$i]} = 1;
            } elsif ( $flags{$ARGV[$i]} =~ /^param$/i ) {
               $flags{$ARGV[$i]} = $ARGV[$i+1];
               $i++;
            }
         } else {
            die "$usage\nThis script was called with an invalid command line flag:  $ARGV[$i]\n";
         }
      } else {
         push @options, $ARGV[$i];
      }
   }

   if ( $#options != ( $args - 1 ) and $args != -1 ) {
      die "$usage\nThis sproc requires $args arguments.  Found " . ( $#options + 1 ) . ".\n";
   }
}


