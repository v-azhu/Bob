use strict;

use File::Basename;
use lib dirname(__FILE__);

use Getopt::Long;
use BundleBuild::RC;
use BundleBuild::Options;
use File::Path qw(remove_tree);

use constant {
    BUNDLE_BUILD_RC_DEPOT => "//depot/tools/dw-rc/...",
    BUNDLE_BUILD_CFG => $ENV{APPDATA}."\\.bundle-build"
};

my $opt_help;
my $opt_target;
my $opt_source;
my $opt_clean;

GetOptions(
    "help|?",		\$opt_help,
    "t|target=s",	\$opt_target,
    "s|source=s",	\$opt_source,
    "c|clean",		\$opt_clean
);

if (defined $opt_help) {
    &printUsage;
    exit(0);
}

if (defined $opt_source && !(-d $opt_source)) {
    printUsage("ERROR: $opt_source doesn't exists\n");
    exit(-1);
}

my $opts = new BundleBuild::Options;
if (defined $opt_target) {
    $opts->{target} = $opt_target;
    $opts->save(BUNDLE_BUILD_CFG);
} else {
    if (-f BUNDLE_BUILD_CFG) {
	$opts->load(BUNDLE_BUILD_CFG);
	if (exists($opts->{target})) {
	    $opt_target = $opts->{target};
	} else {
	    &printUsage("ERROR:\tCannot find target property in '".BUNDLE_BUILD_CFG."'.\n\tUse -target option!\n");
	    exit(-1);
	}
    } else {
	&printUsage("ERROR:\tCannot find the config file '".BUNDLE_BUILD_CFG."'.\n\tUse -target option!\n");
	exit(-1)
    }
}

if (defined $opt_clean) {
    remove_tree($opt_target) if (-d $opt_target);
    # Remove PWD environment variable.
    # When remove_tree is called, PWD env variable
    # is created. Unfortunately, P4 will use this
    # variable. When you change the folder in MS-DOS
    # PWD is not updated to reflect the current working
    # directory, which cause P4 command fail because
    # P4 search the path of PWD to find p4.ini.
    delete $ENV{PWD};
}

# load options from persistent file if it exists
my $rc = new BundleBuild::RC( {
	"depot" => BUNDLE_BUILD_RC_DEPOT,
	"target" => $opt_target,
	"source" => $opt_source
    });

$rc->start;

sub printUsage {
    my ($error) = @_;
    my $name = basename(__FILE__);

    if (defined $error) {
	print $error."\n";
    }

    print <<EOF;
Usage: $name [-clean] [-target PATH] [-source PATH] [-help]

Create a BundleBuild environment using the latest release candidate. A DOS command prompt is started where you can run the bundle build script and keep your current BundleBuild copy untouched.

-help		print this help
-clean		clean the target folder first
-target	PATH	where to put the copy of RC version of Bundle Build Scripts.
		If not provided, a default value saved in a file .bundle-build
		in your HOME directory will be used.
-source PATH	Copy RC version from the specified path instead of
		syncing from the perforce depot. Usually this is only for
		testing used by a developer. 
EOF
}
