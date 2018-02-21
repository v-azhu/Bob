package BundleBuild::Options;

use strict;

sub new {
    my ($class) = @_;

    my $self = {}; 
    bless $self, $class;

    return $self;
}

sub load {
    my ($self, $file) = @_;
    open(FILE, $file) || return 0;
    my @lines = <FILE>;
    close(FILE);

    for my $line (@lines) {
	$line =~ s/^\s+|\s+$//g;
	my ($key, $val) = split(/\s*=\s*/, $line);
	$self->{$key} = $val;
    }
    
    return 1;
}

sub save {
    my ($self, $file) = @_;
    open (FILE, ">$file") || die ("Cannot open $file to write bundle build options: $!");
    while (my($key,$val) = each(%$self)) {
	print FILE "$key=$val\n";
    }
    close (FILE);
}

1;
