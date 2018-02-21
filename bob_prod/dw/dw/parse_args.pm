=head1 NAME

parse_args - module for parsing command line

=head1 SYNOPSIS

# Add the directory that the script runs in to @INC so that we can find the perl modules.
BEGIN { $dir = $0; $dir =~ s/\\/\//g; $dir =~ s/\/[^\/]+$//; push @INC, $dir; }

use strict;
use warnings;
use dw::parse_args;


$FlagConfig{'dbtype'}      = [    'arg', 'Specify connection type ( db2 or sql, db2 is default )' ];
$FlagConfig{'E'}           = [ 'no arg', 'trusted connection' ];

&process_cmd_line;

print "FLAGS:\n";
foreach my $flag ( sort keys %flags ) {
   print "$flag - '" . $flags{$flag} . "'\n";
}

print "\nARGS:\n";
foreach my $arg ( sort @args ) {
   print "$arg\n";
}

=head1 DESCRIPTION

This module allows us to easily parse arguments passed to a script
and returns usage text when someone specifies an invalid argument
or calls for usage help.

=cut

package dw::parse_args;

use strict;
use warnings;
use Exporter();
use DynaLoader();
use Carp;
use dw::general;

BEGIN {
   our ( $VERSION, $P4FILE, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS );

   $VERSION       = sprintf "%d", '$Revision: #4 $' =~ /(\d+)/;
   $P4FILE        = sprintf "%s", '$File: //depot/Tools/dw/dw/parse_args.pm $' =~ /^\$[F]ile: (.+) \$$/;

   @ISA           = qw(Exporter DynaLoader);
   @EXPORT        = qw( %FlagConfig %flags @args &process_cmd_line &usage_and_die $helptext_addition $scriptname );
   %EXPORT_TAGS   = ( );         # eg:  TAG => [ qw!name1 name2! ],

   # your exported package globals go here,
   # as well as any optionally exported functions
   #@EXPORT_OK     = qw($Var1 %Hashit &func3);

   # Check version
   if ( ! $ENV{SKIP_VERSION_CHECK} ){
      my $p4_version = `p4 files $P4FILE 2>&1`;
      if ( $? != 0 ) { confess $p4_version . "\n\n" . "Could not run command, p4 files $P4FILE:  $!" }

      chomp ( $p4_version );
      $p4_version =~ s/^.*#(\d+).*?$/$1/;

      if ($VERSION != $p4_version) {
         confess "Your version of, $P4FILE, is $VERSION.  Perforce has version $p4_version.  Please sync your file and try again.\n\nProcess died";
      }
   }
}

=item %FlagConfig

Configuration data structure for command line parsing and generating usage text.
This is a hash of arrays.  Each key will correspond to a command line argument.
the value will be a two element array.

The first element will either be 'arg' or 'no arg'.  This specifies if the flag
should have an argument or not.

The second element will be the text that should be included in the command line
usage text for the command line flag being defined.

=cut

our %FlagConfig;

$FlagConfig{'?'} = [ 'no arg', 'Show syntax summary.' ];

=item %FlagConfig

This hash is set by the process_cmd_line subroutine.  There will be a key for
every command line flag that was specified when calling the routine.  If the
flag was configured with 'arg', the value will be the argument to the flag.
If the flag was configured with 'no arg', the value will be 1, indicating it
was passed in.

=cut

our %flags;

=item @args

Contains every value of @ARGV that is not a command line flag or an argument
to a flag.

=cut

our @args;

=item $helptext_addition

Contains additional text to add to the beginning of helptext.  This may be used
to better describe the process or provide usage info dealing with non-flag
arguments being passed.

=cut

our $helptext_addition;

=item $scriptname

Contains the name of the script that was run.

=cut

our $scriptname;

$scriptname = $0;
$scriptname =~ s/^.*?([^\/\\]+)$/$1/;

# Internal vars
my $helptext;

=item process_cmd_line

This sproc is what is used to actually process the command line.

=cut

sub process_cmd_line {
   my $arg;
   my $CustomFlagsRegEx;
   my $flag;
   my $help;
   my $i;
   my $opt;
   my $padding;
   my $RegEx;
   my %CustomFlags;

   # Build helptext
   $helptext  = "\nusage:  $scriptname\n\n";
   if ( $helptext_addition ) { $helptext .= "  " . $helptext_addition . "\n\n"; }
   $i = 1;

   $padding = ( sort { $b <=> $a } map ( length ( $_ ), keys (%FlagConfig) ) )[0] + 1; # max length of keys + 1
   foreach $opt ( sort { lc $a cmp lc $b } keys %FlagConfig ) {
      $helptext .= "  [-$opt]";
      $helptext .= " " x ( $padding - length ( $opt ) );
      $helptext .= $FlagConfig{$opt}[1] . "\n";
   }

   $helptext .= "\n";

   # Parse command line
   for ( $i = 0; $i <= $#ARGV; $i++ ) {
      undef $arg;
      if ( $ARGV[$i] =~ /^[\/\-](.*)$/ ) {
         $flag = $1;
         if ( $flag =~ /^\?/ ) { die ( $helptext . "Printing command line usage.\n" ) };

         if ( defined $FlagConfig{$flag} ) {
            if ( $FlagConfig{$flag}[0] eq 'no arg' ) {
               $arg = 1;
            } elsif ( $FlagConfig{$flag}[0] eq 'arg' ) {
               if ( $i eq $#ARGV ) {
                  &usage_and_die ( "An argument is required for flag:  " . $ARGV[$i] );
               }
               $arg = $ARGV[++$i];
            }
            $flags{$flag} = $arg;
         } else {
            #push @args, $ARGV[$i];
            &usage_and_die ( "process was called with invalid flag:  -" . $flag );
         }
      } else {
         push @args, $ARGV[$i];
      }
   }
}

=item usage_and_die

Prints the command line usage and the message associated with it, then dies.

=cut

sub usage_and_die {
   my $msg = shift;

   &log_and_die ( $helptext . "\n\n" . $msg );
}

=head1 AUTHOR

Aaron Dillow E<lt>adillow@expedia.comE<gt>.

=head1 COPYRIGHT

(C) 2010 Expedia, Inc. All rights reserved.

=cut

1;  # Modules must return a true value
