
my %flags;
my @options;
my $usage;
my $hasflags;

$divider = "#############################################################################\n";

# Handle command line parsing.
%flags = (
     '-a'      => 'no param'
   , '-b'      => 'no param'
   , '-c'      => 'no param'
   , '-m'      => 'no param'
   , '-u'      => 'no param'
   , '-r'      => 'no param'
);

$usage   =
   "\ncl [-u] raid#\n\n" .
   "   raid#   This is the raid number that is to be reported on.\n" .
   "   -a      Display affected dbs for raid.\n" .
   "   -b      Display batch file contents for raid.\n" .
   "   -c      Display the contents of the raid.txt file.\n" .
   "   -m      Display manual steps for raid.\n" .
   "   -r      Display latest listing of file revs for this raid (inc cl #).\n" .
   "   -u      Display unique listing of files that were part of this raid.\n\n";

&ProcessCmdLine ( 1 );

( $raid ) = @options;

if ( $raid !~ /^\d+$/ ) {
   die "$usage\nThe raid number should be numeric:  $!\n";
}

$hasflags = 0;

foreach my $val ( %flags ) {
   $hasflags = $val if ( $val eq 1 );
}

$flags{"No flags"} = $hasflags;
$flags{"No flags"} =~ tr/01/10/;

$DisplayObject{"Affected DB"}{"-a"} = 1;

$DisplayObject{"Manual Steps"}{"-m"} = 1;

$DisplayObject{"Batch Content"}{"-b"} = 1;

$DisplayObject{"Affected DB"}{"-r"} = 1;
$DisplayObject{"Manual Steps"}{"-r"} = 1;
$DisplayObject{"Batch Content"}{"-r"} = 1;
$DisplayObject{"Distinct Files With Rev"}{"-r"} = 1;

$DisplayObject{"Affected DB"}{"-u"} = 1;
$DisplayObject{"Manual Steps"}{"-u"} = 1;
$DisplayObject{"Batch Content"}{"-u"} = 1;
$DisplayObject{"Distinct Files"}{"-u"} = 1;

$DisplayObject{"Affected DB"}{"No flags"} = 1;
$DisplayObject{"Manual Steps"}{"No flags"} = 1;
$DisplayObject{"Batch Content"}{"No flags"} = 1;
$DisplayObject{"All Changelists"}{"No flags"} = 1;


$raidfile = &raidfile_name ( 'dmo', $raid );

$raidfile = &raidfile_name ( 'edw', $raid ) if ( &DoesP4FileExist ( $raidfile ) == 0 );

if ( $flags{'-c'} eq 1 ) {
   $command = "p4 print $raidfile";

   open ( RAID, "$command 2>&1 |" ) or die "Couldn't run command $command:  $!\n";

   while ( <RAID> ) {
      print $_;
   }

   close ( RAID );
} else {
   &process_raid_file;
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
   
   return ( $output =~ /(?:no such file| - delete)/ ? 0 : 1 );
}

sub process_raid_file {
   $sProvider     = 'SQLOLEDB';

   # Do the work
   $command = "p4 print $raidfile";

   open ( RAID, "$command 2>&1 |" ) or die "Couldn't run command $command:  $!\n";

   $line = 0;
   while ( <RAID> ) {
      $line++;
      chomp;

      if ( /no such file/ ) {
         print "$divider## No raid file exists for raid $raid\n$divider\n";
         exit ( 0 );
      }

      # Determine what section we are in
      if ( /^\s*\[Section:.*\]\s*$/i || /^\s*\[end\]\s*$/i ) {
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
            push @changelists, $1;
         } else {
            die "ERROR:  Malformed line in raid $raid line $line:\n   $_\n";
         }
      }

      # Find all databases that code will be affected
      if ( $section =~ /^VBCode$/i ) {
         next if ( /^\s*$/ );
         if ( /sDatabaseFolder\s*=\s*['"]([^'"]+)['"]/i ) {
            $sDatabaseFolder = $1;
         } elsif ( /sDatabaseName\s*=\s*['"]([^'"]+)['"]/i ) {
            $sDatabaseName = $1;
         } elsif ( /sServerName\s*=\s*['"]([^'"]+)['"]/i ) {
            $sServerName = $1;
         } elsif ( /sProvider\s*=\s*['"]([^'"]+)['"]/i ) {
            $sProvider = $1;
         } elsif ( /sSchemaName\s*=\s*['"]([^'"]+)['"]/i ) {
            $sDatabaseName = $1;
         } elsif ( /BundleHotfixAdd\s*\(\s*['"]([^'"]+)['"]/i ) {
            $BundleHotfixAdd = $1;
            $sProvider = "SQL Server" if ( $sProvider =~ /sqloledb/i );
            $dbs{$sProvider}{$sServerName}{$sDatabaseName}{$sDatabaseFolder}{$BundleHotfixAdd} = 1;
         } elsif ( /BOEDWUNV\s+(.+?)\s*,\s+(.+?)\s*,\s+(.+?)\s*$/i ) {
            $folder  = &resolve_vars($1);
            $biar    = &resolve_vars($2);
            $conn    = &resolve_vars($3);
            
            $bo{"universes"}{$folder}{$biar} = 1;
         } elsif ( /BOEDWBIAR\s+(.+?)\s*,\s+(.+?)\s*,\s+(.+?)\s*$/i ) {
            $bo_type    = &resolve_vars($1);
            $bo_folder  = &resolve_vars($2);
            $bo_biar    = &resolve_vars($3);
            $bo{lc($bo_type)}{$bo_folder}{$bo_biar} = 1;
         } elsif ( /^\s*([\w_]+)\s*=\s*(.*?)\s*$/ ) {
            $var_name   = $1;
            $var_val    = &resolve_vars($2);

            $variables{$var_name} = $var_val;
         } elsif ( $_ !~ /s(?:Test|RC|PPE|Dev)(?:DatabaseName|ServerName|SchemaName)/i and $_ !~ /^\s*'/ ) {
            print "WARNING:  Unrecognized line ( line $line ) could be an error:\n   $_\n";
         }
      }

      # Find all manual steps
      if ( $section =~ /^ManualSteps$/i ) {
         if ( not defined $ManualSteps ) {
            next if ( /^\s*$/ );
            $ManualSteps = "$_\n";
         } else {
            $ManualSteps .= "$_\n";
         }
      }

      # Find all command line steps
      if ( $section =~ /^BatFileContents$/i ) {
         if ( not defined $BatFileContents ) {
            next if ( /^\s*$/ );
            $BatFileContents = "$_\n";
         } else {
            $BatFileContents .= "$_\n";
         }
      }
   }

   close ( RAID );

   # Get changelist info
   for ( $x = 0; $x <= $#changelists; $x++ ) {
      $changelist = $changelists[$x];
      undef $desc;
      $command = "p4 describe -s $changelist";

      open ( CL, "$command |" ) or die "Couldn't run command $command:  $!\n";

      while ( <CL> ) {
         if ( ( not defined $desc{$changelist} ) and ( not /^Change $changelist by/ ) and ( not /^\s*$/ ) ) {
            if ( /^\s*(.+?)\s*$/ ) {
               $desc{$changelist} = "Changelist $changelist - $1";
            }
         }
         if ( /^\.\.\. (.*)(#\d+)\s+(\w+)\s*$/ ) {
            $file                            = $1;
            $rev                             = $2;
            $change_type                     = $3;
            $rev_info                        = $1 . $2 . $3;
            $changes{$changelist}{$rev_info} = 1;
            $files{uc($file)}{'filename'}    = $file;
            $files{uc($file)}{'rev'}         = $rev;
            $files{uc($file)}{'change_type'} = $change_type;
            $files{uc($file)}{'change_list'} = $changelist;
         }
      }

      close ( CL );
   }


   # Affected DB
   if ( &DisplaySection("Affected DB") eq 1 ) {
      print $divider . "## Affected databases - $raid\n" . $divider;

      foreach $prv ( sort keys %dbs ) {
         foreach $srv ( sort keys %{ $dbs{$prv} } ) {
            foreach $db ( sort keys %{ $dbs{$prv}{$srv} } ) {
               printf "%10s - %s.%s\n", $prv, $srv, $db;
            }
         }
      }
      print "\n";

      print $divider . "## Affected BO Objects - $raid\n" . $divider;
      foreach $bo_type ( sort keys %bo ) {
         foreach $bo_folder ( sort keys %{ $bo{$bo_type} } ) {
            foreach $bo_biar ( sort keys %{ $bo{$bo_type}{$bo_folder} } ) {
               printf "%10s - %s\\%s\n", $bo_type, $bo_folder, $bo_biar;
            }
         }
      }
      print "\n";
   }

   # Manual Steps
   if ( &DisplaySection("Manual Steps") eq 1 ) {
      print $divider . "## Manual Steps - $raid\n" . $divider;
      print "$ManualSteps";
      print "\n";
   }

   # Batch Content
   if ( &DisplaySection("Batch Content") eq 1 ) {
      print $divider . "## Batch File Contents - $raid\n" . $divider;
      print "$BatFileContents";
      print "\n";
   }

   # Distinct Files
   if ( &DisplaySection("Distinct Files") eq 1 ) {
      print $divider . "## Files - $raid\n" . $divider;

      foreach $file ( sort keys %files ) {
         print "$files{$file}{'filename'}";
         if ( $files{$file}{'change_type'} eq 'delete' ) {
            print " $files{$file}{'change_type'}";
         }
         print "\n";
      }
      print "\n";
   }
   
   # Distinct Files With Rev
   if ( &DisplaySection("Distinct Files With Rev") eq 1 ) {
      print $divider . "## Files - $raid\n" . $divider;

      foreach $file ( sort keys %files ) {
         print "$files{$file}{'filename'}$files{$file}{'rev'}";
         print " cl:$files{$file}{'change_list'}";
         if ( $files{$file}{'change_type'} eq 'delete' ) {
            print " $files{$file}{'change_type'}";
         }
         print "\n";
      }
      print "\n";
   }

   # All Changelists
   if ( &DisplaySection("All Changelists") eq 1 ) {
      print $divider . "## Changelists - $raid\n" . $divider;

      for ( $x = $#changelists; $x >= 0; $x-- ) {
         $changelist = $changelists[$x];
         print "$desc{$changelist}\n\n";
         foreach $file ( sort keys %{ $changes{$changelist} } ) {
            print "$file\n";
         }
         print "\n";
      }
   }
}

sub DisplaySection {
   my ( $SectionName, $flag );

   ( $SectionName ) = @_;

   foreach $flag ( keys %flags ) {
      if ( $flags{$flag} eq 1 ) {
         if ( $DisplayObject{$SectionName}{$flag} eq 1 ) {
            return 1;
         }
      }
   }
   return 0;
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

   if ( $#options != ( $args - 1 )  ) {
      print "test\n";
      die "$usage\nThis script requires $args arguments.  Found " . ( $#options + 1 ) . ".\n";
   }
}

sub resolve_vars {
   my $val = shift;

   if ( $val =~ /^"(.*)"$/ ) {
      return $1;
   } else {
      foreach $var ( keys %variables ) {
         if ( $val eq $var ) {
            return $variables{$var};
         }
      }
   }
   return $val;
}

