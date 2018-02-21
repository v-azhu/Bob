=head1 NAME

dw - general purpose perl module for expedia's edw team

=head1 SYNOPSIS

use dw;

=head1 DESCRIPTION

The intent of the dw module is to have a single place to house
all common functionality needed by perl scripts used by the
Expedia team.

=cut

package dw::general;

use strict;
use warnings;
use Exporter();
use DynaLoader();
use Carp;
use File::Path qw(make_path);

BEGIN {
   our ( $VERSION, $P4FILE, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

   $VERSION       = sprintf "%d", '$Revision: #5 $' =~ /(\d+)/;
   $P4FILE        = sprintf "%s", '$File: //depot/Tools/dw/dw/general.pm $' =~ /^\$[F]ile: (.+) \$$/;

   @ISA           = qw(Exporter DynaLoader);
   @EXPORT        = qw(
                     &timestamp
                     &run_cmd
                     &run_cmd_allout
                     &split_filename
                     &write_text_to_file
                     &append_text_to_file
                     &generate_random_string
                     &check_version
                     &log_and_die
                     &read_file
                     &run_cmd_allout_error
                    );
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

#################################################################
# Subroutines
#################################################################

=item timestamp

Returns a timestamp.

=cut

sub timestamp {
   my (
      $hour,                  # Hours
      $isdst,                 # Is Daylight Saving Time
      $mday,                  # Day of Month
      $min,                   # Minutes
      $mon,                   # Month
      $sec,                   # Seconds
      $timestamp,             # Text of debug message
      $wday,                  # Day of Week
      $yday,                  # Day of Year
      $year                   # Year
   );
   ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime ( time );

   $year += 1900;
   $mon++;
   $timestamp = sprintf ( "%4d-%2.2d-%2.2d %2.2d:%2.2d:%2.2d", $year, $mon, $mday, $hour, $min, $sec );
   return ( $timestamp );
}

=item run_cmd

Runs a command and returns stdout as an array.

=cut

sub run_cmd {
   my $command = shift;
   my $results;

   $results = `$command`;

   if ( $? != 0 ) { &log_and_die ( $results . "Could not run command, $command:  $!" ) }

   return ( $results );
}

=item run_cmd_allout

Runs a command and returns stdout and stderr as a list.  Will die with errors.

=cut

sub run_cmd_allout {
   my $command = shift;
   my $results;

   $results = `$command 2>&1`;

   if ( $? != 0 ) { &log_and_die ( $results . "Could not run command, $command:  $!" ) }

   return ( $results );
}

=item run_cmd_allout_error

Runs a command and returns stdout and stderr as a list.  Will not die with errors.

=cut

sub run_cmd_allout_error {
   my $command = shift;
   my $results;

   $results = `$command 2>&1`;

   return ( $results, $?, $! );
}


=item split_filename

Splits a directory and filename.

=cut

sub split_filename {
   my $fullpath = shift;
   my $dir;
   my $file;

   $fullpath =~ s/\//\\/g;

   if ( $fullpath =~ /(:?.*\\)?([^\\]+)$/ ) {
      $dir  = $1;
      $file = $2;
   }

   return ( $dir, $file );
}

=item write_text_to_file

Writes text to a file.  If a reference is passed in, dereference.

=cut

sub write_text_to_file {
   my $local_file = shift;
   my $content    = shift;

   my $path;
   my $file;
   my $fh;

   ( $path, $file ) = &split_filename ( $local_file );

   &make_path ( $path );

   open ( $fh, "> $local_file" ) || &log_and_die ( "Could not open file, $local_file, for writing:  $!" );

   if ( ref ( $content ) ) {
      print $fh ${ $content };
   } else {
      print $fh $content;
   }

   close ( $fh );
}

=item append_text_to_file

Writes text to a file.  If a reference is passed in, dereference.

=cut

sub append_text_to_file {
   my $local_file = shift;
   my $content    = shift;

   my $path;
   my $file;
   my $fh;

   ( $path, $file ) = &split_filename ( $local_file );

   &make_path ( $path );

   open ( $fh, ">> $local_file" ) || &log_and_die ( "Could not open file, $local_file, for writing:  $!" );

   if ( ref ( $content ) ) {
      print $fh ${ $content };
   } else {
      print $fh $content;
   }

   close ( $fh );
}

=item generate_random_string

Generates a text string of random characters.  The length of the string is specified
by the argument being passed to it.

=cut

sub generate_random_string {
   my $length_of_randomstring = shift;
   my @chars = ('a'..'z','A'..'Z','0'..'9','_');
   my $random_string;

   # rand @chars will generate a random number between 0 and scalar @chars
   foreach (1..$length_of_randomstring) {
      $random_string .= $chars[rand @chars];
   }
   return $random_string;
}

=item check_version

=cut

sub check_version {
   my $script_location  = shift;
   my $script_version   = shift;

   if ( ! $ENV{SKIP_VERSION_CHECK} ){
      my $p4_version = &run_cmd_allout ( "p4 files $script_location" );

      chomp ( $p4_version );
      $p4_version =~ s/^.*#(\d+).*?$/$1/;

      if ($script_version != $p4_version) {
         &log_and_die ( "Your version of, $script_location, is $script_version.  Perforce has version $p4_version.  Please sync your file and try again." );
      }
   }
}

=item log_and_die

=cut

sub log_and_die {
   my $message       = shift;
   my $line          = "*" x 50;

   $message = "\n\n$line\n*                     ERROR                      *\n$line\n\n$message\n\n\n$line\n\nProcess died";
   &confess ( $message );
}

=item read_file

=cut

sub read_file {
   my $filename      = shift;
   my $file;
   my $term;

   open ( FILE, $filename ) || &log_and_die ( "Could not open file, $filename, for reading:  $!" );
   $term = $/;
   undef $/;
   $file = <FILE>;
   $/ = $term;
   close ( FILE );

   return $file;
}

=head1 AUTHOR

Aaron Dillow E<lt>adillow@expedia.comE<gt>.

=head1 COPYRIGHT

(C) 2010 Expedia, Inc. All rights reserved.

=cut

1;  # Modules must return a true value
