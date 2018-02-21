=head1 NAME

dw::p4 - logging module for expedia's edw team

=head1 SYNOPSIS

use dw::p4;

=head1 DESCRIPTION

dw::p4 is a perl module for interacting with the perforce
repository.

=cut

package dw::p4;

use strict;
use warnings;
use Exporter();
use DynaLoader();
use Carp;
use Data::Dumper;
use dw::general;
use dw::log;
use Cwd 'abs_path';
use File::Path qw(make_path);

# For gracefully handling ctrl-c
$SIG{INT} = sub { die "Died with ctrl-c.  Exiting gracefully.\n"; };

BEGIN {
   our ( $VERSION, $P4FILE, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

   $VERSION       = sprintf "%d", '$Revision: #10 $' =~ /(\d+)/;
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

   if ( $self->{label_created} ) {
      print "Deleting label:  " . $self->{label} . "\n";
      $cmd = "p4 -c " . $self->{client} . " label -d " . $self->{label};
      print `$cmd`;
      if ( $? != 0 ) { print "Could not delete label:  $!\n" }
   }

   if ( $self->{client_created} ) {
      print "Deleting client:  " . $self->{client} . "\n";
      $cmd = "p4 -c " . $self->{client} . " revert //...";
      print `$cmd`;
      print `p4 client -d $self->{client}`;
      if ( $? != 0 ) { die ( "Could not delete client:  $!" ) }
   }
}

#####################################################################
# Initialize p4 object
#####################################################################

=over

=item new

A new instance of the p4 object can be created by calling the new
method.  It can be called without arguments or with a hash.

=cut

sub new {
   my %initialize;

   shift;
   if (@_) { %initialize = @_ }

   my $self = {
        log_obj                     => dw::log->new( stdout_log_level => 3 )
      , p4port                      => "perforce:1985"
      , local_base                  => "."
      , source_branch               => "dev"
      , dest_branch                 => "main"
      , depot                       => "depot"
      , depot_branch                => "EDW"
      , remove_branch               => 1
      , remove_depot_branch         => 1
      , remove_depot                => 1
      , p4_files                    => $ENV{"TEMP"} . "\\dw\\P4_FILES\\" . $$
      , client_description          => "Created by p4.pm."
      , client_root                 => "."
      , client                      => &generate_random_string(11)
      , label                       => "label_" . &generate_random_string(11)
      , delete_client_after_submit  => 1
      , submit_desc                 => getlogin() . " - Submitted by p4.pm"
   };

   if ( %initialize ) { $self = { %$self, %initialize } }

   bless ( $self );
   return $self;
}

#####################################################################
# Methods to access object data
#####################################################################

=item p4port

This methods sets/returns the perforce server and port to be used when
connecting.

=cut

sub p4port {
   my $self = shift;
   if (@_) { $self->{p4port} = shift }
   return $self->{p4port};
}

=item depot_branch

This methods sets/returns the depot_branch that we are using.

=cut

sub depot_branch {
   my $self = shift;
   if (@_) { $self->{depot_branch} = shift }
   return $self->{depot_branch};
}

=item source_branch

This methods sets/returns the source_branch that we are using.

=cut

sub source_branch {
   my $self = shift;
   if (@_) { $self->{source_branch} = shift }
   return $self->{source_branch};
}

=item local_base

This methods sets/returns the local_base property.  This is the directory
that will be used as a base for where the file will be synced to.

=cut

sub local_base {
   my $self = shift;
   if (@_) { $self->{local_base} = shift }
   return $self->{local_base};
}

=item client_root

This methods sets/returns the client_root property.  This is the directory
that will be used as a base for where the file will be synced to.

=cut

sub client_root {
   my $self = shift;
   if (@_) { $self->{client_root} = shift }
   return $self->{client_root};
}

=item workspace_dir

This methods sets/returns the workspace_dir property.  This indicates
files should be pulled to this specific directory in the workspace.

=cut

sub workspace_dir {
   my $self = shift;
   if (@_) { $self->{workspace_dir} = shift }
   return $self->{workspace_dir};
}

=item remove_path

This methods sets/returns the path string that will be removed when
pulling files.

For example if you are trying to retrieve:

   //depot/Tools/dw/BuildScripts/DBBuild.vbs

You could set remove_path to:

   depot/Tools/dw/BuildScripts

Then the file would be retrieved to the base directory.

=cut

sub remove_path {
   my $self = shift;
   my $val  = shift;

   if ($val) {
      $val =~ s/^\/\///;   # Remove leading \\
      $self->{remove_path} = $val;
   }
   return $self->{remove_path};
}

=item file_rev

This returns the rev of the file last pulled through the print method.

=cut

sub file_rev {
   my $self = shift;
   return $self->{file_rev};
}

=item file_name

This returns the name of the file last pulled through the print method.

=cut

sub file_name {
   my $self = shift;
   return $self->{file_name};
}

=item submit_desc

This methods sets/returns the description to be used when submitting
a raid.

=cut

sub submit_desc {
   my $self = shift;
   if (@_) { $self->{submit_desc} = shift }
   return $self->{submit_desc};
}

#####################################################################
# General methods
#####################################################################

=item add

Adds file to perforce

=cut

=item submit

Submit changelist.

=cut

sub submit {
   my $self       = shift;
   my $cmd        = "submit";

   if ( $self->{files_to_submit} ) {
      $self->{log_obj}->c ( "minor", "Submitting changelist" );

      # Include a comment if there is one
      if ( $self->{submit_desc} ) { $cmd .= " -d \"" . $self->{submit_desc} . "\""; }

      $self->run_perforce_cmd ( $cmd );
      undef $self->{files_to_submit};
   } else {
      $self->{log_obj}->c ( "minor", "No files to submit." );
   }

   if ( $self->{delete_client_after_submit} ) { $self->delete_client }
}

=item integrate_file

Itegrate files from source_branch to dest_branch.

=cut

sub integrate_file {
   my $self       = shift;
   my $file       = shift;
   my $file_base  = $file;
   my $response;

   if ( $file =~ /\/$self->{source_branch}\//i ) {
      $file_base =~ s/#\d+$//;
      $file_base =~ s/$self->{source_branch}/$self->{dest_branch}/i;

      $self->create_client;
      $self->{log_obj}->c ( "minor", "Integrating file:  " . $file );

      $response = $self->run_perforce_cmd ( "integ -t -i -v -d \"$file\" \"$file_base\"" ) . "\n";

      if ( $response =~ /all revision\(s\) already integrated/m ) {
         $self->{log_obj}->c ( "minor", "File already integrated." );
      } else {
         $response = $self->run_perforce_cmd ( "resolve -at" ) . "\n";
         $self->{files_to_submit} = 1;
      }
   }
}

=item create_client

Creates a perforce client

=cut

sub create_client {
   my $self          = shift;
   my $logfile;
   my $path          = &abs_path( $self->{client_root} );
   my $line;
   my $view;

   if ( ! $self->{client_created} ) {
      $self->{log_obj}->c ( "minor", "Creating client:  " . $self->{client} );
      $logfile = $self->{p4_files};
      if ( $self->{p4_files} !~ /[\\\/]$/ ) { $logfile .= "\\" }
      $logfile .= "client.cfg";

      $self->{client_spec} = "

         Client:        " . $self->{client} . "
         Owner:         " . getlogin() . "
         Description:   " . $self->{client_description} . "
         Root:          " . $self->{client_root} . "
         Options:       noallwrite noclobber nocompress unlocked nomodtime normdir
         LineEnd:       local
         View:
      ";

      $self->{client_spec} =~ s/^\s+//gm;

      if ( $self->{client_view} ) {
         foreach my $line ( @{ $self->{client_view} } ) {
            $view .= "   ";
            $view .= ( $line->[0] =~ /\s/ ) ? "\"" . $line->[0] . "\"" : $line->[0];
            $view .= " ";
            $view .= ( $line->[1] =~ /\s/ ) ? "\"" . $line->[1] . "\"" : $line->[1];
            $view .= "\n";
         }
         $view =~ s/#\d+//g;
         $self->{client_spec} .= $view;
      } else {
         $self->{client_spec} .= "   //$self->{depot}/... //" . $self->{client} . "/...\n";
      }

      &write_text_to_file ( $logfile, $self->{client_spec} );
      $self->run_perforce_cmd ( "client -i < $logfile" );
      $self->{client_created} = 1;
   }
}

=item delete_client

Deletes the current perforce client.

=cut

sub delete_client {
   my $self          = shift;

   if ( $self->{client_created} ) {
      $self->{log_obj}->c ( "minor", "Deleting client:  " . $self->{client} );
      $self->run_perforce_cmd ( "revert //..." );
      undef $self->{client_created};
      $self->run_perforce_cmd ( "client -d " . $self->{client} )
   }
}

=item print

Returns the contents of a file in perforce.

=cut

sub print {
   my $self = shift;
   my $file = shift;
   my $first_line;
   my $results;

   $self->{log_obj}->c ( "debug", "Fetch file contents for:  " . $file );

   $results = $self->run_perforce_cmd ( "print $file" );

   if ( $results =~ /\A(.*?$)\n(.*)\Z/ms ) {
      $first_line = $1;
      $results    = $2;
      if ( $first_line =~ /(\/\/.*?)#(\d+)/ ) {
         $self->{file_name}   = $1;
         $self->{file_rev}    = $2;
      }
   }

   $self->{log_obj}->c ( "debug", "Fetched file:  " . $first_line );

   return $results;
}

=item files

Returns array of hashes for all files in perforce specified by a string that was passed in.

=cut

sub files {
   my $self          = shift;
   my $p4_file_path  = shift;

   my $result;
   my $file;
   my $rev;
   my $change_type;
   my $changelist;
   my $file_type;

   my %results;

   $self->{log_obj}->c ( "debug", "Find all files at:  " . $p4_file_path );

   $result = $self->run_perforce_cmd ( "files $p4_file_path" );

   if ( $result =~ /no such file\(s\)\./ ) {
      $self->{log_obj}->c ( "minor", "No files found at:  " . $p4_file_path );
   } else {
      foreach ( split /\r?\n/, $result ) {
         if ( /^(\/\/$self->{depot}.+?)#(\d+) - ([\w\/]+) change (\d+) \(([^\)]+)\)/ ) {
            ( $file, $rev, $change_type, $changelist, $file_type ) = ( $1, $2, $3, $4, $5 );
            $results{$file}{"rev"}        = $rev;
            $results{$file}{"change_type"} = $change_type;
            $results{$file}{"changelist"} = $changelist;
            $results{$file}{"file_type"}  = $file_type;
         } else {
            &log_and_die ( "Unrecognized line in p4 files output:  $_" );
         }
      }
   }

   return \%results;
}

=item get

Gets file from perforce to corresponding place in localbase.

=cut

sub get {
   my $self          = shift;
   my $p4_file_path  = shift;

   my $file_mapping;
   my $p4_file;

   $file_mapping = $self->_file_mapping ( $p4_file_path, $self->{local_base} );

   foreach $p4_file ( sort keys %$file_mapping ) {
      $self->{log_obj}->c ( "debug", "Fetch file:  " . $p4_file );
      $self->get_file_to_location( $p4_file, $file_mapping->{$p4_file} );
   }
}

=item get_file_to_location

Gets file from perforce to a local file.

=cut

sub get_file_to_location {
   my $self       = shift;
   my $p4_file    = shift;
   my $local_file = shift;

   $self->{log_obj}->c ( "debug", "Fetch file to disk:  " . $p4_file );

   $self->run_perforce_cmd ( "print -q -o $local_file $p4_file" );

   $self->{log_obj}->c ( "debug", "Fetched file to:  " . $local_file );
}

=item add_view_mapping

Adds entry(s) to view mapping definition.

=cut

sub add_view_mapping {
   my $self          = shift;
   my $p4_file_path  = shift;

   my $file_mapping;
   my $p4_file;
   my $workspace_dir = "//" . $self->{client};;

   if ( $self->{workspace_dir} ) { $workspace_dir .= "/" . $self->{workspace_dir}; }
   $file_mapping = $self->_file_mapping ( $p4_file_path, $workspace_dir );

   foreach $p4_file ( sort keys %$file_mapping ) {
      $self->{log_obj}->c ( "debug", "Add to client view:  " . $p4_file );
      push @{ $self->{client_view} }, [ $p4_file, $file_mapping->{$p4_file} ];
   }
}

=item sync_view

Syncs client view to local directory.

=cut

sub sync_view {
   my $self          = shift;

   $self->create_client();

   $self->{log_obj}->c ( "minor", "Syncing client..." );
   $self->run_perforce_cmd ( "sync -p" );
}

=item changelist

Returns hash of all files and their revisions that are associated with a changelist.

=cut

sub changelist {
   my $self = shift;
   my $changelist = shift;
   my $results;
   my $file;
   my $rev;
   my $change_type;
   my %return;

   $self->{log_obj}->c ( "debug", "Fetch changelist contents for:  " . $changelist );

   $results = $self->run_perforce_cmd ( "describe -s $changelist" );

   if ( $results =~ /no such changelist/ ) { &log_and_die ( "Invalid changelist:  $changelist" ); }

   foreach ( split /\r?\n/, $results ) {
      if ( /^\.\.\. (.*)#(\d+)\s+(\w+)\s*$/ ) {
         $file          = $1;
         $rev           = $2;
         $change_type   = $3;

         $return{$file}{$rev} = $change_type;
      }
   }

   return %return;
}

=item changelists

Returns array of all files and their revisions that are associated with a changelist.

=cut

sub changelists {
   my $self = shift;
   my $p4_file = shift;
   my $results;
   my @return;

   $self->{log_obj}->c ( "debug", "Fetch all changelists associated with:  " . $p4_file );

   $results = $self->run_perforce_cmd ( "filelog $p4_file" );

   foreach ( split /\r?\n/, $results ) {
      if ( /^\.\.\. #\d+ change (\d+)/ ) {
         push @return, $1;
      }
   }

   return @return;
}

=item exists

Tests for existance of a file in perforce.

=cut

sub exists {
   my $self = shift;
   my $file = shift;
   my $results;

   $self->{log_obj}->c ( "debug", "Test for existance of file:  " . $file );

   $results = $self->run_perforce_cmd ( "fstat $file" );

   if ( $results =~ /- no such file\(s\)./ || $results =~ /headAction delete/ ) {
      $self->{log_obj}->c ( "debug", "File does not exist in perforce." );
      return 0;
   } else {
      $self->{log_obj}->c ( "debug", "File exists in perforce." );
      return 1;
   }
}

=item dump_object

Dumps the contents of an object.

=cut

sub dump_object {
   my $self = shift;

   return Dumper($self);
}

=item run_perforce_cmd

Runs a perforce command and returns the results.  checks to make sure
there is an open connection.

=cut

sub run_perforce_cmd {
   my $self = shift;
   my $cmd = shift;
   my $return;

   if ( $self->{client_created} ) { $cmd = '-c ' . $self->{client} . ' ' . $cmd }
   $cmd = "p4 $cmd";
   $self->{log_obj}->c ( "debug", "Running perforce command:  $cmd" );
   $return = join "", &run_cmd_allout ( $cmd );

   if ( $return =~ /Your session has expired, please login again./ ) { &log_and_die ( "Please login to perforce before running." ) }

   return $return;
}


#####################################################################
# Internal methods
#####################################################################

=item _file_mapping

Internal method for creating a file mapping for fetching files.

=cut

sub _file_mapping {
   my $self          = shift;
   my $p4_file_path  = shift;
   my $local_base    = shift;
   my %return;

   my $files;
   my $p4_file;
   my $local_file;
   my $branch        = $self->{source_branch};
   my $depot         = $self->{depot};
   my $depot_branch  = $self->{depot_branch};

   if ( $p4_file_path =~ /(?:\.\.\.|\*)/ ) {
      $files = $self->files ( $p4_file_path );
   } else {
      $files = { $p4_file_path => {} };
   }

   foreach $p4_file ( sort keys %$files ) {
      if ( ( ! $files->{$p4_file}->{"change_type"} ) || $files->{$p4_file}->{"change_type"} ne "delete" ) {
         $local_file = $p4_file;
         $p4_file .= "#" . $files->{$p4_file}->{"rev"} if ( $files->{$p4_file}->{"rev"} );

         $local_base =~ s/\\$//;                # remove trailing \ if there is one

         if ( $self->{remove_path} ) {
            $local_file =~ s/$self->{remove_path}//i;
            $local_file =~ s/^\/\/\//\/\//;     # If local_file starts with /// now, change to //
         }

         $local_file =~ s/#.*$//;               # Strip rev if there is one

         $local_file =~ s/^\/\//$local_base\//; # Put this in local base

         # If we are configured to remove the branch, do it.
         if ( $self->{remove_branch} ) {
            $local_file =~ s/\/$branch\//\//i;   # First occurance only
         }

         # If we are configured to remove the depot, do it.
         if ( $self->{remove_depot} ) {
            $local_file =~ s/\/$depot\//\//i;   # First occurance only
         }

         # If we are configured to remove the depot, do it.
         if ( $self->{remove_depot_branch} ) {
            $local_file =~ s/\/$depot_branch\//\//i;   # First occurance only
         }

         if ( $self->{local_base} && $local_base eq $self->{local_base} ) {
            $local_file =~ s/\//\\/g;              # DOS format
         }

         $return{$p4_file} = $local_file;
      }
   }

   return \%return;
}

=back

=cut

=head1 AUTHOR

Aaron Dillow E<lt>adillow@expedia.comE<gt>.

=head1 COPYRIGHT

(C) 2011 Expedia, Inc. All rights reserved.

=cut

1;  # Modules must return a true value

