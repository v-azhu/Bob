
# Add the directory that the script runs in to @INC so that we can find the perl modules.
BEGIN { $dir = $0; $dir =~ s/\\/\//g; $dir =~ s/\/[^\/]+$//; push @INC, $dir; }

use dw::general;
use dw::raid;
use dw::log;
use dw::parse_args;

# Parse command line
$FlagConfig{'from'}     = [    'arg', 'Branch to integrate from.  If unspecified defaults to dev.' ];
$FlagConfig{'to'}       = [    'arg', 'Branch to integrate to.  If unspecified defaults to main.' ];
$FlagConfig{'debug'}    = [ 'no arg', 'Increase logging.' ];
$FlagConfig{'v'}        = [ 'no arg', 'Returns the current version of the script and dies.' ];

$helptext_addition = "raid [raid [raid...]]";

&process_cmd_line;

# Declare variables
my $version    = sprintf "%d", '$Revision: #6 $' =~ /(\d+)/;
my $file       = sprintf "%s", '$File: //depot/Tools/dw/integrate.pl $' =~ /^\$[F]ile: (.+) \$$/;
my $log_level  = ( $flags{'debug'} ) ? 0 : 3;
my $from       = ( $flags{'from'} ) ? $flags{'from'} : 'dev';
my $to         = ( $flags{'to'} ) ? $flags{'to'} : 'main';

if ( $flags{'v'} ) { die $scriptname . " - Version " . $version . "\n"; }

&check_version ( $file, $version );

# Validate command line
if ( $#args == -1 ) {
   &usage_and_die ( "Please specify at least one raid number." );
}

# Initialize objects
$log = dw::log->new( stdout_log_level => 3 );

if ( $flags{'debug'} ) {
   $log->file_log_level($log_level);
   $log->log_file("integrate.log");
}

$raid = dw::raid->new(
     log_obj               => $log
   , p4_files              => $ENV{"TEMP"}
   , die_if_no_raid_file   => 0
   , source_branch         => $from
   , dest_branch           => $to
);

$log->c ( "debug", $scriptname . " called with:  " . join ( " ", @ARGV ) );
$log->c ( "minor", "Integrate from " . $from . " to " . $to . "." );

# Loop through raids passed on command line and integrate.
foreach $raid_num ( @args ) {
   if ( $raid_num =~ /^\d+$/ ) {
      $log->c ( "major", "Integrate raid:  " . $raid_num );
      $raid->raid($raid_num);
      $raid->integrate_raid;
   } else {
      &usage_and_die ( "Invalid argument.  Please only specify raid numbers" );
   }
}

