

use strict;

my %flags;
my @options;
my $usage;
my $raid;
my $raidnumber;

$usage =
   "\nReturnRaidNum.pl [RaidFile] | [Raid#]\n\n" .
   "   Set environment variable RaidNum to the raid number or\n" .
   "   or raid number of the file passed in.\n\n" .
   "   RaidFile   This is the perforce path of a raid file\n" .
   "   Raid#      The is the raid number of a raid file\n\n";

&ProcessCmdLine ( 1 );

( $raid ) = @options;

if ( $raid !~ /^\d+$/ ) {
   if ( $raid =~ /\/\/depot\/(?:dmo|edw)\/Common\/DBBuild\/DEV\/db\/HotFix\/Bundles\/RaidFiles\/Raid(\d+)\.txt/i ) {
      $raid = $1;
   } else {
      die "Malformed raid:  $raid\nPlease specify a raid number or the perforce path to a raid file.\n";
   }
}


print $raid;

#######################################################################################
# Subroutines
#######################################################################################

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


