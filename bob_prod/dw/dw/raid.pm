=head1 NAME

dw::raid - raid bug module

=head1 SYNOPSIS

use dw::raid;

$p4 = dw::raid->new(
     raid               => 73971
   , log_obj            => dw::log->new( log_file => "log.txt", stdout_log_level => 0 )
);

$line = '#' x 70;

print "$line\n# Raid.txt details\n$line\n";

print "Raid.txt file:  "   . $p4->raid_file . "\n\n";
print "Raid.txt branch:  " . $p4->raid_branch . "\n\n";
print "Raid.txt contents:\n" . $p4->raid_file_contents . "\n\n";

print "$line\n# Raid.txt section details\n$line\n";

if ( $p4->manualsteps_section )     { print "manualsteps:\n" . $p4->manualsteps_section . "\n\n"; }
if ( $p4->vbcode_section )          { print "vbcode:\n" . $p4->vbcode_section . "\n\n"; }
if ( $p4->batfilecontents_section ) { print "batfilecontents:\n" . $p4->batfilecontents_section . "\n\n"; }
if ( $p4->changelists_section )     { print "changelists:\n" . $p4->changelists_section . "\n\n"; }

print "$line\n# Changelists\n$line\n";

foreach $cl ( $p4->changelists ) {
   print "$cl\n";
}

=head1 DESCRIPTION

dw::raid is a perl module for gathering information about a particular raid.
It caches information it already pulled to provide consistant reporting and
reduce the amount of time it takes to gather information.

=cut

package dw::raid;

use strict;
use warnings;
use Exporter();
use DynaLoader();
use Carp;
use Data::Dumper;
use dw::general;
use dw::log;
use dw::p4;

BEGIN {
   our ( $VERSION, $P4FILE, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

   $VERSION       = sprintf "%d", '$Revision: #11 $' =~ /(\d+)/;
   $P4FILE        = sprintf "%s", '$File: //depot/Tools/dw/dw/raid.pm $' =~ /^\$[F]ile: (.+) \$$/;

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

#####################################################################
# Initialize p4 object
#####################################################################

=item new

A new instance of the p4 object can be created by calling the new
method.  It can be called without arguments or with a hash.

=cut

sub new {
   my %initialize;

   shift;
   if (@_) { %initialize = @_ }

   my $self = {
        log_obj               => dw::log->new( stdout_log_level => -1 )
      , die_if_no_raid_file   => 1
      , source_branch         => "dev"
      , dest_branch           => "main"
   };

   if ( %initialize ) { $self = { %$self, %initialize } }

   $self->{p4_obj} = dw::p4->new(
        log_obj         => $self->{log_obj}
      , source_branch   => $self->{source_branch}
      , dest_branch     => $self->{dest_branch}
      , local_base      => $self->{local_base}
      , substitute_from => $self->{substitute_from}
      , substitute_to   => $self->{substitute_to}
   );

   if ( $self->{raiddir} && $self->{raiddir} !~ /\\$/ ) { $self->{raiddir} .= "\\"; }

   bless ( $self );
   return $self;
}

#####################################################################
# Methods to access object data
#####################################################################

=item raid

This methods retrieves/sets the raid number to find info for.  This
property must be set before doing most things.

=cut

sub raid {
   my $self = shift;
   if (@_) { $self->{raid} = shift }
   return $self->{raid};
}

=item raiddir

This specifies a directory to be used instead of perforce.  If this
is undefined, perforce will be used.

=cut

sub raiddir {
   my $self = shift;
   if (@_) { $self->{raiddir} = shift }
   if ( $self->{raiddir} && $self->{raiddir} !~ /\\$/ ) { $self->{raiddir} .= "\\"; }
   return $self->{raiddir};
}

=item source_branch

This specifis a the name of the branch that files will be sourced from.

=cut

sub source_branch {
   my $self = shift;
   if (@_) {
      $self->{source_branch} = shift;
      $self->{p4_obj}->source_branch($self->{source_branch});
   }
   return $self->{source_branch};
}

#####################################################################
# General methods
#####################################################################

=item dump_object

Dumps the contents of an object.

=cut

sub dump_object {
   my $self = shift;

   return Dumper($self);
}

=item raid_file

Returns the perforce path of the raid.txt file.

=cut

sub raid_file {
   my $self = shift;
   
   $self->_get_raid_file_branch;
   return $self->{$self->{raid}}->{file};
}

=item raid_file

Returns the perforce path of the raid.txt file.

=cut

sub raid_file_rev {
   my $self = shift;
   
   $self->_get_raid_file_branch;
   return $self->{$self->{raid}}->{raid_file}->{file_rev};
}

=item raid_file_contents

Returns the contents of the raid.txt file.

=cut

sub raid_file_contents {
   my $self = shift;
   
   $self->_get_raid_file_contents;

   return $self->{$self->{raid}}->{raid_file}->{file_contents};
}

=item raid_branch

Returns the perforce branch of the raid.txt file.

=cut

sub raid_branch {
   my $self = shift;
   
   $self->_get_raid_file_branch;
   return $self->{$self->{raid}}->{branch};
}

=item manualsteps_section

Returns the text of the manualsteps section of the raid.

=cut

sub manualsteps_section {
   my $self = shift;
   
   $self->_get_raid_file_contents;

   return $self->{$self->{raid}}->{raid_file}->{sections}->{manualsteps};
}

=item all_manualsteps

Returns all manual steps from all raids pulled by current instance of the
object consolidate into one string.

=cut

sub all_manualsteps {
   my $self = shift;

   $self->_get_raid_file_contents;

   return $self->{all_raids}->{sections}->{manualsteps}
}

=item vbcode_section

Returns the text of the vbcode section of the raid.

=cut

sub vbcode_section {
   my $self = shift;
   
   $self->_get_raid_file_contents;

   return $self->{$self->{raid}}->{raid_file}->{sections}->{vbcode};
}

=item all_vbcode

Returns all vbcode from all raids pulled by current instance of the
object consolidate into one string.

=cut

sub all_vbcode {
   my $self = shift;

   $self->_get_raid_file_contents;

   return $self->{all_raids}->{sections}->{vbcode};
}

=item DeployObjects

Returns what objects we should be deploying using link files.  This comes from parsing out
calls to DeployObjects from the vbs section.  This returns for current raid only.

=cut

sub DeployObjects {
   my $self = shift;

   $self->_get_raid_file_contents;

   return sort keys %{ $self->{$self->{raid}}->{derived}->{DeployObjects} };
}

=item all_DeployObjects

Returns DeployObjects consolidated from all raids.

=cut

sub all_DeployObjects {
   my $self = shift;

   $self->_get_raid_file_contents;

   return sort keys %{ $self->{all_raids}->{derived}->{DeployObjects} };
}

=item batfilecontents_section

Returns the text of the batfilecontents section of the raid.

=cut

sub batfilecontents_section {
   my $self = shift;
   
   $self->_get_raid_file_contents;

   return $self->{$self->{raid}}->{raid_file}->{sections}->{batfilecontents};
}

=item all_batfilecontents

Returns all batfilecontents from all raids pulled by current instance of the
object consolidate into one string.

=cut

sub all_batfilecontents {
   my $self = shift;

   $self->_get_raid_file_contents;

   return $self->{all_raids}->{sections}->{batfilecontents}
}

=item changelists_section

Returns the text of the changelists section of the raid.

=cut

sub changelists_section {
   my $self = shift;
   
   $self->_get_raid_file_contents;

   return $self->{$self->{raid}}->{raid_file}->{sections}->{changelists};
}

=item changelists

Returns the text of the changelists section of the raid.

=cut

sub changelists {
   my $self = shift;
   
   $self->_get_raid_file_contents;

   if ( $self->{$self->{raid}}->{raid_file}->{changelists} ) {
      return @{ $self->{$self->{raid}}->{raid_file}->{changelists} };
   } else {
      $self->{log_obj}->c ( "minor", "The raid.txt doesn't contain any changelists:  " . $self->{raid} );
      return undef;
   }
}

=item max_files

Returns a reference to a hash that is formatted as follows:

{<P4 FILEPATH>} = {
     rev          => <rev>
   , changetype   => <changetype>
}

=cut

sub max_files {
   my $self = shift;

   $self->_get_changelist_files;

   return $self->{$self->{raid}}->{raid_file}->{files}->{maxrev};
}

=item integrate_raid

Itegrate all files in raid from source_branch to dest_branch.

=cut

sub integrate_raid {
   my $self       = shift;
   my %files;
   my $file;
   my $file_rev;
   my $tmp_desc;
   my $skip_dir   = "//depot/EDW/Dev";

   # If there isn't a raid.txt file skip.
   if ( $self->raid_file ) {
      # Sometimes raid.txt files only have manual steps.  In these cases skip this section
      if ( $self->max_files ) {
         %files = %{ $self->max_files };

         # Integrate raid.txt file
         $self->{p4_obj}->integrate_file($self->{$self->{raid}}->{file});

         # Integrate all other files
         foreach $file ( sort keys %files ) {
            if ($file =~ /^$skip_dir/i) {
               print "*********Not integrating file: \n";
               print $file;
            } else {
               $file_rev = $file . "#" . $files{$file}->{rev};
               $self->{p4_obj}->integrate_file($file_rev);
            }
         }

         $tmp_desc = $self->{p4_obj}->submit_desc;    # Remember the previous description.
         $self->{p4_obj}->submit_desc( "Integration for raid " . $self->{raid} . " submitted by " . getlogin() . " using raid.pm" );

         $self->{p4_obj}->submit;

         $self->{p4_obj}->submit_desc( $tmp_desc );    # Return the previous description.
      }
   } else {
      $self->{log_obj}->c ( "minor", "Skipping integration due to no raid.txt file:  " . $self->{raid} );
   }
}

#####################################################################
# Internal methods
#####################################################################

=head2 INTERNALS

=item _get_changelist_files

Build a data structure holding file(s), their revs, and what action was taken
on the file.  This will be collected for all files on a raid.

=cut

sub _get_changelist_files {
   my $self = shift;
   my $changelist;
   my %files;

   if ( ! defined $self->{$self->{raid}}->{raid_file}->{files} ) {
      if ( $self->changelists ) {
         # Loop through changelists and find all files and revs.
         foreach $changelist ( $self->changelists ) {
            $self->{log_obj}->c ( "minor", "Getting files associated with changelist:  $changelist" );
            
            %files = $self->{p4_obj}->changelist($changelist);

            foreach my $file ( sort keys %files ) {
               foreach my $rev ( sort { $a <=> $b } keys %{ $files{$file} } ) {
                  $self->{$self->{raid}}->{raid_file}->{files}->{revs}->{$file}->{$rev} = $files{$file}{$rev};
                  $self->{$self->{raid}}->{raid_file}->{files}->{maxrev}->{$file}->{rev} = $rev;
                  $self->{$self->{raid}}->{raid_file}->{files}->{maxrev}->{$file}->{changetype} = $files{$file}{$rev};
               }
            }
         }
      }
   }
}

=item _get_raid_file_contents

Parse out the raid.txt file into seperate sections.

=cut

sub _get_raid_file_contents {
   my $self = shift;
   my $section;
   my $changelist = 0;

   if ( ! defined $self->{$self->{raid}}->{raid_file}->{file_contents} ) {
      $self->{log_obj}->c ( "minor", "Retrieving raid.txt file and parsing contents:  " . $self->{raid} );
      if ($self->{raiddir}) {
         # Read raid.txt file from file instead of perforce
         $self->{$self->{raid}}->{raid_file}->{file_contents} = &read_file($self->raid_file);
         $self->{$self->{raid}}->{raid_file}->{file_rev} = "from local file";
         $self->{log_obj}->c ( "minor", "Retrieved raid.txt file rev:  " . $self->{$self->{raid}}->{raid_file}->{file_rev} );
      } else {
         $self->{$self->{raid}}->{raid_file}->{file_contents} = $self->{p4_obj}->print($self->raid_file);
         $self->{$self->{raid}}->{raid_file}->{file_rev} = $self->{p4_obj}->file_rev;
         $self->{log_obj}->c ( "minor", "Retrieved raid.txt file rev:  " . $self->{$self->{raid}}->{raid_file}->{file_rev} );
      }

      # Break raid.txt file into seperate sections
      foreach ( split "\n", $self->{$self->{raid}}->{raid_file}->{file_contents} ) {
         if ( /^\s*\[Section:\s*(.*?)\s*\]\s*$/i ) {
            $section = lc ( $1 );
            $self->{log_obj}->c ( "debug", "Parsing out details for section:  " . $section );
            if ( $section !~ /^manualsteps|vbcode|batfilecontents|changelists|jars$/ ) {
               &log_and_die ( "Unrecognized section:  " . $section );
            }
         } elsif ( /^\s*\[end\]\s*$/i ) {
            undef $section;
         } elsif ( defined $section ) {
            $self->{$self->{raid}}->{raid_file}->{sections}->{$section} .= "$_\n";
         }
      }

      # Loop through each section.  If it only contains whitespace, undef it.
      foreach $section ( keys %{ $self->{$self->{raid}}->{raid_file}->{sections} } ) {
         if ( $self->{$self->{raid}}->{raid_file}->{sections}->{$section} =~ /^\s+$/s ) {
            $self->{log_obj}->c ( "debug", "The $section section is empty, undef." );
            undef $self->{$self->{raid}}->{raid_file}->{sections}->{$section}
         }
      }

      # Consolidate manualsteps section
      if ( $self->{$self->{raid}}->{raid_file}->{sections}->{manualsteps} ) {
         $self->{all_raids}->{sections}->{manualsteps} .= ( "#" x 50 ) . "\n";
         $self->{all_raids}->{sections}->{manualsteps} .= "# Manual steps for raid " . $self->{raid} . "\n";
         $self->{all_raids}->{sections}->{manualsteps} .= ( "#" x 50 ) . "\n";
         $self->{all_raids}->{sections}->{manualsteps} .= $self->{$self->{raid}}->{raid_file}->{sections}->{manualsteps} . "\n\n";
      }

      # Consolidate vbcode section
      if ( $self->{$self->{raid}}->{raid_file}->{sections}->{vbcode} ) {
         $self->{all_raids}->{sections}->{vbcode} .= ( "'" x 50 ) . "\n";
         $self->{all_raids}->{sections}->{vbcode} .= "'' VBS code for raid " . $self->{raid} . "\n";
         $self->{all_raids}->{sections}->{vbcode} .= ( "'" x 50 ) . "\n";
         $self->{all_raids}->{sections}->{vbcode} .= $self->{$self->{raid}}->{raid_file}->{sections}->{vbcode} . "\n\n";
      }

      # Consolidate batfilecontents section
      if ( $self->{$self->{raid}}->{raid_file}->{sections}->{batfilecontents} ) {
         $self->{all_raids}->{sections}->{batfilecontents} .= "rem " . ( "#" x 50 ) . "\n";
         $self->{all_raids}->{sections}->{batfilecontents} .= "rem " . "# BAT code for raid " . $self->{raid} . "\n";
         $self->{all_raids}->{sections}->{batfilecontents} .= "rem " . ( "#" x 50 ) . "\n";
         $self->{all_raids}->{sections}->{batfilecontents} .= $self->{$self->{raid}}->{raid_file}->{sections}->{batfilecontents} . "\n\n";
      }

      if ( $self->{$self->{raid}}->{raid_file}->{sections}->{vbcode} ) {
         foreach ( split "\n", $self->{$self->{raid}}->{raid_file}->{sections}->{vbcode} ) {
            if ( /DeployObjects\s*\(\s*['"]([^'"]+)['"]\s*\)/i ) {
               $self->{$self->{raid}}->{derived}->{DeployObjects}->{$1} = 1;
               $self->{all_raids}->{derived}->{DeployObjects}->{$1} = 1;
            }
         }
      }

      if ( $self->{source_branch} =~ /^dev$/i ) {
         # Parse out changelists
         if ( $self->{$self->{raid}}->{raid_file}->{sections}->{changelists} ) {
            $self->{log_obj}->c ( "debug", "Parsing out changelist section." );
            foreach ( split "\n", $self->{$self->{raid}}->{raid_file}->{sections}->{changelists} ) {
               s/\s*#.*$//;
               s/\s+//g;
               next if ( /^$/ );
               if ( /^(\d+)$/ ) {
                  if ( $changelist >= $1 ) { &log_and_die ( "Changelists must be in order:  $changelist, $1\n" ) }
                  $changelist = $1;
                  push @{ $self->{$self->{raid}}->{raid_file}->{changelists} }, $changelist;
               } else {
                  &log_and_die ( "ERROR:  Malformed line in raid $self->{raid}:\n   $_\n" );
               }
            }
         }
      } else {
         push @{ $self->{$self->{raid}}->{raid_file}->{changelists} }, $self->{p4_obj}->changelists($self->raid_file);
      }
   }
}

=item _get_raid_file_branch

Finds the file path and branch of the raid.txt file.

=cut

sub _get_raid_file_branch {
   my $self = shift;
   
   if ( ! defined $self->{raid} ) { &log_and_die ( "Must set raid property." ) }

   if ( ! defined $self->{$self->{raid}}->{file} ) {
      if ($self->{raiddir}) {
         $self->{$self->{raid}}->{file} = $self->{raiddir} . "raid" . $self->{raid} . ".txt";
         $self->{$self->{raid}}->{branch} = "file";
      } else {
         if ( $self->{p4_obj}->exists("//depot/edw/Common/DBBuild/" . $self->{source_branch} . "/db/hotfix/bundles/RaidFiles/Raid" . $self->{raid} . ".txt") ) {
            $self->{$self->{raid}}->{file} = "//depot/edw/Common/DBBuild/" . $self->{source_branch} . "/db/hotfix/bundles/RaidFiles/Raid" . $self->{raid} . ".txt";
            $self->{$self->{raid}}->{branch} = "edw";
         } elsif ( $self->{p4_obj}->exists("//depot/edw/Common/DBBuild/" . $self->{source_branch} . "/db/hotfix/bundles/RaidFiles/archive/Raid" . $self->{raid} . ".txt") ) {
            $self->{$self->{raid}}->{file} = "//depot/edw/Common/DBBuild/" . $self->{source_branch} . "/db/hotfix/bundles/RaidFiles/archive/Raid" . $self->{raid} . ".txt";
            $self->{$self->{raid}}->{branch} = "edw";
         } elsif ( $self->{p4_obj}->exists("//depot/dmo/Common/DBBuild/" . $self->{source_branch} . "/db/hotfix/bundles/RaidFiles/Raid" . $self->{raid} . ".txt") ) {
            $self->{$self->{raid}}->{file} = "//depot/dmo/Common/DBBuild/" . $self->{source_branch} . "/db/hotfix/bundles/RaidFiles/Raid" . $self->{raid} . ".txt";
            $self->{$self->{raid}}->{branch} = "dmo";
         } else {
            if ( $self->{die_if_no_raid_file} ) {
               &log_and_die ( "No raid.txt file was found for raid:  " . $self->{raid} );
            } else {
               $self->{log_obj}->c ( "minor", "No raid.txt file was found for raid:  " . $self->{raid} );
            }
         }
      }
   }
}

=head1 AUTHOR

Aaron Dillow E<lt>adillow@expedia.comE<gt>.

=head1 COPYRIGHT

(C) 2010 Expedia, Inc. All rights reserved.

=cut

1;  # Modules must return a true value

