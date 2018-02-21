=head1 NAME

dw::query - module for querying databases

=head1 SYNOPSIS

   use strict;
   use dw::query;

   # Declare variable
   my $q;

   # Initialize query object
   $q = dw::query->new();

   # Initialize connection
   $q->server_type("db2");
   $q->server("devedw");
   $q->schema("edw");
   $q->user("edwdbldr");
   $q->pass("Edw%4dev");

   # Define and execute query
   $q->sql("select * from soa_svc_dest_tbl");
   $q->execute();

   # Loop through results
   while ( $q->nextrow() ) {
      print $q->getval("soa_svc_dest_tbl_schema_name") . "\n";
   }

=head1 DESCRIPTION

dw::query is a perl module for interacting with databases

=cut

package dw::query;

use strict;
use warnings;
use Exporter();
use DynaLoader();
use Carp;
use Data::Dumper;
use dw::general;
use dw::log;
use DBI;
#use Cwd 'abs_path';
#use File::Path qw(make_path);

# For gracefully handling ctrl-c
$SIG{INT} = sub { die "Died with ctrl-c.  Exiting gracefully.\n"; };

BEGIN {
   our ( $VERSION, $P4FILE, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

   $VERSION       = sprintf "%d", '$Revision: #6 $' =~ /(\d+)/;
   $P4FILE        = sprintf "%s", '$File: //depot/Tools/dw/dw/p4.pm $' =~ /^\$[F]ile: (.+) \$$/;

   @ISA           = qw(Exporter DynaLoader);
   @EXPORT        = qw();

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

sub DESTROY {
   my $self = shift;
   my $cmd;

   if ( $self->{sth} ) {
      print "Closing statement handler.\n";
      $self->{sth}->finish;
      undef $self->{sth};
   }

   if ( $self->{dbh} ) {
      print "Disconnecting from server:  " . $self->{server} . "\n";
      $self->{dbh}->disconnect;
      undef $self->{dbh};
   }
}

#####################################################################
# Initialize p4 object
#####################################################################

=over

=item new

A new instance of the query object can be created by calling the new
method.  It can be called without arguments or with a hash.

=cut

sub new {
   my %initialize;

   shift;
   if (@_) { %initialize = @_ }

   my $self = {
        log_obj                     => dw::log->new( stdout_log_level => 3 )
      , server_type                 => "db2"
      , ignore_missing_column       => 0
   };

   if ( %initialize ) { $self = { %$self, %initialize } }

   bless ( $self );
   return $self;
}

#####################################################################
# Public Properties
#####################################################################

=item server_type

Sets the type of server that should be connected to.

=cut

sub server_type {
   my $self = shift;
   if (@_) { $self->{server_type} = lc ( shift ) }
   if ( $self->{server_type} !~ /^(?:db2|sql)$/ ) {
      &log_and_die ( "Valid server types are db2 or sql.  You specified:  " . $self->{server} );
   }
   return $self->{server_type};
}

=item server

Sets the name of the server to connect to.

=cut

sub server {
   my $self = shift;
   if (@_) { $self->{server} = shift }
   return $self->{server};
}

=item sql

Sets the sql statement to run.

=cut

sub sql {
   my $self = shift;
   if (@_) {
      $self->{sql} = shift;
      $self->sth_close();
   }
   return $self->{sql};
}

=item pass

Sets the password to connect to the database with

=cut

sub pass {
   my $self = shift;
   if (@_) { $self->{pass} = shift }
   return $self->{pass};
}

=item user

Sets the username to connect to the database with

=cut

sub user {
   my $self = shift;
   if (@_) { $self->{user} = shift }
   return $self->{user};
}

=item database

Sets the database to connect to ( for sql server ).

=cut

sub database {
   my $self = shift;
   if (@_) { $self->{database} = shift }
   return $self->{database};
}

=item schema

Sets the schema to connect to ( for db2 ).

=cut

sub schema {
   my $self = shift;
   if (@_) { $self->{schema} = uc ( shift ) }
   return $self->{schema};
}

=item ignore_missing_column

If set to 1 then return undefined when a column name is asked for
that is not in the dataset.  Otherwise die with error.

=cut

sub ignore_missing_column {
   my $self = shift;
   if (@_) { $self->{ignore_missing_column} = shift }
   return $self->{ignore_missing_column};
}

#####################################################################
# General methods
#####################################################################

=item execute

Executes query.

=cut

sub execute {
   my $self       = shift;

   my %attr;
   my $name;
   my $i;

   $attr{'HandleError'} = sub { &log_and_die ( shift ) };

   if ( $self->{server_type} eq 'db2' ) {
      $attr{'db2_set_schema'} = $self->{schema} if ( $self->{schema} );
   }

   $self->{log_obj}->c ( "minor", "Connecting to:  " . $self->conn_str() );
   $self->{dbh} = DBI->connect( $self->conn_str(), $self->{user}, $self->{pass}, \%attr )
      or &ErrorAndDie ( "Can't connect to database: $DBI::errstr" );

   $self->sth_close();
   $self->{sth} = $self->{dbh}->prepare($self->{sql});
   $self->{sth}->execute();

   # Create has of element positions
   foreach $name ( @{ $self->{sth}->{NAME} } ) {
      $self->{element}->{lc($name)} = $i++;
   }
}

=item name

Returns name of column.

=cut

sub name {
   my $self       = shift;
   my $element    = shift;

   return $self->{sth}->{NAME}[$element];
}

=item element

Returns column number by name.

=cut

sub element {
   my $self       = shift;
   my $name       = shift;

   return $self->{element}->{lc($name)};
}

=item getval

Returns the value of a column from name of column.

=cut

sub getval {
   my $self       = shift;
   my $name       = shift;

   if ( ! defined $self->{element}->{lc($name)} ) {
      if ( $self->{ignore_missing_column} ) {
         return undef;
      } else {
         &log_and_die ( "No column defined with the name:  " . $name );
      }
   } else {
      return ${$self->{row}}[$self->{element}->{lc($name)}];
   }
}

=item nextrow

Returns the next row and sets row number.

=cut

sub nextrow {
   my $self       = shift;
   my $nextrow;

   $self->{row} = $self->{sth}->fetchrow_arrayref;

   if ( $self->{row} ) {
      #$self->{row} = \$nextrow;
      $self->{rownumber}++;
      return 1;
   } else {
      return 0;
   }
}

=item sth_close

Close the currently open statement handler.

=cut

sub sth_close {
   my $self       = shift;

   if ( $self->{sth} ) {
      $self->{log_obj}->c ( "minor", "Closing statement handler." );
      $self->{sth}->finish;
      undef $self->{sth};
   }

   undef $self->{element};
   undef $self->{row};
   $self->{rownumber} = 0;
}

=item dbh_close

Close the currently open database connection.

=cut

sub dbh_close {
   my $self       = shift;

   if ( $self->{dbh} ) {
      $self->{log_obj}->c ( "minor", "Disconnecting from server:  " . $self->{server} );
      $self->{dbh}->disconnect;
      undef $self->{dbh};
   }
}

=back

=cut

#####################################################################
# private methods
#####################################################################

sub conn_str {
   my $self = shift;

   my $conn;

   if ( $self->{server_type} eq 'db2' ) {
      $conn =  "dbi:DB2:" . $self->{server};
   } else {
      $conn = "dbi:ODBC:driver={sql server};server=" . $self->{server} . ";";
      $conn .= "database=" . $self->{database} . ";" if ( $self->{database} );
   }

   return $conn;
}

=head1 AUTHOR

Aaron Dillow E<lt>adillow@expedia.comE<gt>.

=head1 COPYRIGHT

(C) 2011 Expedia, Inc. All rights reserved.

=cut

1;  # Modules must return a true value

