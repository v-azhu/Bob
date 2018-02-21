=head1 NAME

dw::log - logging module for expedia's edw team

=head1 SYNOPSIS

use dw::log;

$log1 = dw::log->new(
     include_timestamp  => 1
   , label              => ""
   , log_dir            => "."
   , log_file           => "log.txt"
   , log_initialized    => 0
   , overwrite_log      => 1
);

$log2 = dw::log->new;

$log3 = dw::log->new;

print "Dump log1\n" . ( '-' x 50 ) . "\n" . $log1->dump_object . "\n\n";
print "Dump log2\n" . ( '-' x 50 ) . "\n" . $log2->dump_object . "\n\n";

$log1->o ( "log1 test" );
$log2->o ( "log1 test" );

print "\n\n\n";

for ( my $x = -1; $x <= 4; $x++ ) {
   $log3->stdout_log_level ( $x );
   $log3->o ( "TEST - " . $log3->stdout_log_level );
   $log3->c ( "exception", "Test exception message." );
   $log3->c ( "major", "Test major message." );
   $log3->c ( "minor", "Test minor message." );
   $log3->c ( "debug", "Test debug message." );
   print "\n";
}

$log1->close_log;
$log2->close_log;
$log3->close_log;

=head1 DESCRIPTION

dw::log is a logging module for the expedia data warehouse.  It
allows you write logs to files or to STDOUT.  Configuration can be set by
passing an implicit hash, or by calling methods to set values.

=cut

package dw::log;

use strict;
use warnings;
use Exporter();
use DynaLoader();
use Carp;
use Data::Dumper;
use dw::general;
use File::Path qw(make_path);

BEGIN {
   our ( $VERSION, $P4FILE, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

   $VERSION       = sprintf "%d", '$Revision: #5 $' =~ /(\d+)/;
   $P4FILE        = sprintf "%s", '$File: //depot/Tools/dw/dw/log.pm $' =~ /^\$[F]ile: (.+) \$$/;

   @ISA           = qw(Exporter DynaLoader);
   @EXPORT        = qw( );
   #@EXPORT        = qw( &close_log &dump_object &include_timestamp &label &log_dir &log_file &new &o &overwrite_log );

   #%EXPORT_TAGS   = ( );         # eg:  TAG => [ qw!name1 name2! ],

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

#####################################################################
# Initialize log object
#####################################################################

=item new

A new instance of the log object can be created by calling the new
method.  It can be called without arguments or with a hash.

=cut

sub new {
   my %initialize;

   shift;
   if (@_) { %initialize = @_ }

   my $self = {
        include_timestamp  => 1
      , label              => ""
      , log_dir            => "."
      , log_file           => "output.log"
      , log_initialized    => 0
      , stdout_log_level   => 0
      , file_log_level     => -1       # Don't log to file by default
      , overwrite_log      => 1
   };

   if ( %initialize ) { $self = { %$self, %initialize } }

   bless ( $self );
   return $self;
} 

#####################################################################
# Methods to access object data
#####################################################################

=item include_timestamp

This method sets and returns the value of the include_timestamp
property.  The default value is 1.  If set to 0, the timestamp will
not be included in the log message.  If an argument is not passed,
the property will retain its existing value.

=cut

sub include_timestamp {
   my $self = shift;
   if (@_) { $self->{include_timestamp} = shift }
   return $self->{include_timestamp};
}

=item label

This method sets and returns the value of the label property.  The
default value is an empty string.  If it is given a value, the value
will be included at the beginning of the line.  This can be useful
for purposes such as recording the name of the script that generated
the log.  If an argument is not passed, the property will retain its
existing value.

=cut

sub label {
   my $self = shift;
   if (@_) { $self->{label} = shift }
   return $self->{label};
}

=item log_dir

This method sets and returns the value of the log_dir property.
The default value is the current working directory, ".".  Log files
will be written to the directory specified by this variable.  If an
argument is not passed, the property will retain its existing value.

=cut

sub log_dir {
   my $self = shift;
   if (@_) {
      $self->{log_dir} = shift;
      $self->close_log;
   }
   return $self->{log_dir};
}

=item log_file

This method sets and returns the value of the log_file property.
The default value is standard out, "STDOUT".  When the value is
"STDOUT" logs will be written to standard out instead of a file,
otherwise log files will be written to the file specified by this
variable.  If an argument is not passed, the property will retain its
existing value.

=cut

sub log_file {
   my $self = shift;
   my $file;

   if (@_) {
      $file = shift;
      if ( $file =~ /^\s*stdout\s*$/i ) { $file = "STDOUT" }
      $self->{log_file} = $file;
      $self->close_log;
   }

   return $self->{log_file};
}

=item stdout_log_level

This method sets and returns the value of the stdoutlog_level property.  When
the category logging methods are used the level of the logging can be throttled.

C<
-1 - Don't log any messages using the category logging methods.
 0 - Log all messages
 1 - Log only "exception" log messages
 2 - Log only "major" or more critical log messages.  Modules should not log here.
 3 - Log only "minor" or more critical log messages.  Modules can log here.
 4 - Log only "debug" or more critical log messages.  Modules can log here.
>

=cut

sub stdout_log_level {
   my $self = shift;

   if (@_) { $self->{stdout_log_level} = shift }
   if ( ! ( $self->{stdout_log_level} =~ /^[01234]$/ or $self->{stdout_log_level} == -1 ) ) {
      &log_and_die ( "The stdout_log_level property was set to \"" . $self->{stdout_log_level} .
                     "\".  Valid values are:  0, 1, 2, 3, 4.  See documentation for details.\n" );
   }
   return $self->{stdout_log_level};
}

=item file_log_level

This method sets and returns the value of the file_log_level property.  When
the category logging methods are used the level of the logging can be throttled.

See documentation for stdout_log_level for definitions of values.

=cut

sub file_log_level {
   my $self = shift;

   if (@_) { $self->{file_log_level} = shift }
   if ( ! ( $self->{file_log_level} =~ /^[01234]$/ or $self->{file_log_level} == -1 ) ) {
      &log_and_die ( "The file_log_level property was set to \"" . $self->{file_log_level} .
                     "\".  Valid values are:  0, 1, 2, 3, 4.  See documentation for details.\n" );
   }
   return $self->{file_log_level};
}

=item overwrite_log

This method sets and returns the value of the log_file property.
The default value is 1.  When the value is 1 pre-existing log files
will be overwritten.  When it is 0, log files will get appended to.
If an argument is not passed, the property will retain its existing
value.

=cut

sub overwrite_log {
   my $self = shift;
   if (@_) { $self->{overwrite_log} = shift }
   return $self->{overwrite_log};
}

#####################################################################
# General methods
#####################################################################

=item o

This is the output method.  It has a small name to minimize the
footprint in the calling code.  If a filehandle is not created, it
will open a new one.

=cut
sub o {
   my $self = shift;
   my $msg  = shift;
   my $dest = shift;

   my $logfile;
   my $filehandle;

   # Prefix lines
   if ( $self->{label} )             { $msg = $self->{label}    . ": " . $msg }  # User defined label
   if ( $self->{category} )          { $msg = $self->{category} . ": " . $msg }  # exception, major, minor, or debug
   if ( $self->{include_timestamp} ) { $msg = &timestamp        . ": " . $msg }  # Timestamp

   # Logic for writing output to the appropriat place
   if ( $dest eq "STDOUT" ) {
      $filehandle = \*STDOUT;
   } else {
      if ( ! $self->{log_initialized} ) { # If log isn't initialized yet.
         $logfile = ( $self->{overwrite_log} ) ? '>' : '>>';
         if ( $self->{log_dir} ) {
            &make_path ( $self->{log_dir} );
            if ( $self->{log_dir} !~ /[\\\/]$/ ) { $logfile .= $self->{log_dir} . "\\" }
         }
         $logfile .= $self->{log_dir} . $self->{log_file};
         open ( $self->{FILEHANDLE}, $logfile ) || &log_and_die ( "Couldn't open logfile, $logfile, for writing:  $!" );
         $self->{log_initialized} = 1;
      }
      $filehandle = $self->{FILEHANDLE};
   }
   print {$filehandle} "$msg\n";
}

=item c

This is an output method used for category logging.  It expects two
parameters.  The first is a catogory, and the second is the message.
It has a small name to minimize the footprint in the calling code.

=cut

sub c {
   my $self = shift;
   my $category = shift;
   my $msg = shift;

   my %level = (
        exception    => 1
      , major        => 2
      , minor        => 3
      , debug        => 4
   );

   if ( ! defined $level{$category} ) {
      &log_and_die ( "The category passed to c was set to \"" . $category .
                     "\".  Valid values are:  exception, major, minor, debug.  See documentation for details.\n" );
   }

   if ( $self->{stdout_log_level} == 0 or $self->{stdout_log_level} >= $level{$category} ) {
      $self->{category} = $category;
      $self->o ( $msg, "STDOUT" );
      undef $self->{category};
   }

   if ( $self->{file_log_level} == 0 or $self->{file_log_level} >= $level{$category} ) {
      $self->{category} = $category;
      $self->o ( $msg, "FILE" );
      undef $self->{category};
   }
}

=item close_log

This method closes any open filehandles.  If logs are being written to
STDOUT, it will not close.

=cut

sub close_log {
   my $self = shift;

   if ( $self->{log_initialized} && $self->{log_file} eq 'STDOUT' ) {
      close ( $self->{FILEHANDLE} );
   }

   $self->{log_initialized} = 0;
}

=item dump_object

This is a debug method used to dump the current configuration of the
object.

=cut

sub dump_object {
   my $self = shift;

   return Dumper($self);
}


=head1 TO DO

* Create property for supressing message type
* Update to work with standard out and/or log.  Maybe seperate log levels for each?
* Create logit function in each pm to record what module log is being written from, and shorten the call.

=head1 AUTHOR

Aaron Dillow E<lt>adillow@expedia.comE<gt>.

=head1 COPYRIGHT

(C) 2010 Expedia, Inc. All rights reserved.

=cut

1;  # Modules must return a true value
