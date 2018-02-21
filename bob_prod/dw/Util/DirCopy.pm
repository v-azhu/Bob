package Util::DirCopy;

use strict;

require Exporter;

our @ISA=qw(Exporter);
our @EXPORT_OK=qw(dircopy);

sub dircopy($$) {
    my ($src, $dest) = @_;

    my $cmd = "xcopy /Y /R /K /E $src\\*.* $dest\\";

    system($cmd) == 0 || die "Cannot copy files from '".$src."' to '".$dest."': $!";
}

1;
