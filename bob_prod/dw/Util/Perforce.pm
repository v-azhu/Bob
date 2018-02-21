package Util::Perforce;

use strict;

sub new {
    my ($class, $p4port) = shift;

    if (!defined $p4port) {
	$p4port = $ENV{'P4PORT'};
    }

    die "ERROR: P4PORT is not set" unless defined $p4port && $p4port ne "";

    my $self = {
	p4port => $p4port
    };

    bless $self, $class;
    return $self;
}

sub newClient {
    my ($self, $spec) = @_;
    my $client = $ENV{USERNAME}."-".time;

    open(FILE, "| p4 -p $self->{p4port} client -i")
    || die "Cannot create the client workspace: $!";
    print FILE <<EOF;
Client: $client
Root: $spec->{root}
View: 
EOF
    while (my($depot, $map)=each(%{$spec->{view}})) {
	print FILE "    $depot //$client/$map\n";
    }
    close(FILE) || die "Failed to create the client workspace!";

    return $client;
}

sub deleteClient {
    my ($self, $client) = @_;
    system("p4 -p $self->{p4port} client -d $client");
}

sub syncLatestRevisions {
    my ($self, $client) = @_;
    system("p4 -p $self->{p4port} -c $client sync");
}

1;

__END__

Ideally, this should be a wrapper class of Perforce P4Perl module. But P4Perl installation may not be trivial. To make it simple, just make this as P4 command wrapper.

=cut
