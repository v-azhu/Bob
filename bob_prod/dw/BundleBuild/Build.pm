package BundleBuild::Build;

use strict;

require Exporter;

our @ISA=qw(Exporter);
our @EXPORT_OK=qw(
   getBuildScriptOptions
   checkIncludingUniverse
   useBoedwbiarForUniverse
   extractJarMappings
   createViewForJars
   appendToFile);

use constant {
    USE_BOEDWBIAR_FOR_UNIVERSE => 1,
    INCLUDE_UNIVERSE => 2
};

sub getBuildScriptOptions($opt_local) {
    my ($opt_local) = @_;
    my ($path, $src);
    if (defined $opt_local) {
	$src = "local";
	$path = "$opt_local\\BuildScripts";
    } elsif (exists $ENV{BUNDLE_BUILD_VER}
	&& $ENV{BUNDLE_BUILD_VER} =~/rc/i) {
	$src = "RC";
	$path = "//depot/tools/dw-rc/BuildScripts/...";
    } else {
	$src = "depot";
	$path = "//depot/tools/dw/BuildScripts/...";
    }
    return ("src" => $src, "path" => $path );
}

sub checkIncludingUniverse() {
   my ($vbsfile) = @_;
   my $bits = 0;

   open(VFILE, $vbsfile) || die "Cannot open $vbsfile to check whether including BO Universe deployment";
   while (my $line=<VFILE>) {
      $line =~ s/^\s+|\s+$//g;

      if ($line =~ /^\s*BOEDWBIAR\s+"Universes"/m) {
	 $bits |= USE_BOEDWBIAR_FOR_UNIVERSE;
      } elsif ($line =~ /BOEDWUNV/) {
	 $bits |= INCLUDE_UNIVERSE;
      }
   }
   close(VFILE);

   return $bits;
}

sub useBoedwbiarForUniverse {
    my ($status) = @_;
    return $status & USE_BOEDWBIAR_FOR_UNIVERSE;
}

sub extractJarMappings() {
    my ($file) = @_;

    open(FILE, $file) || die ("Cannot open file $file: $!");
    my $mappings = {};
    while (my $line = <FILE>) {
	$line =~ s/^\s*|\s*$//g;
	if (length($line) > 0) {
	    my ($depot, $dest) = split(/\s+/, $line);
	    die ("Invalid P4 view mapping:\n $line\n") if (not defined $dest); 
	    $mappings->{$depot} = $dest;
	}
    }
    close(FILE);

    return $mappings;
}

sub createViewForJars() {
    my ($folder, $mappings) = @_;
    my $view = "";
    while (my ($depot, $dest)= each(%$mappings)) {
	$dest = "/".$dest unless $dest =~ /^\// && $folder !~ /\/$/;
	$view .= "   ".$depot." ".$folder.$dest."\n";
    }
    return $view;
}

sub appendToFile() {
    my ($file, $content) = @_;
    open(FILE, ">> $file") || die "Cannot open $file for appending: $!";
    print FILE $content;
    close(FILE);
}
