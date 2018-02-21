package BundleBuild::RC;

use strict;
use Util::Perforce;
use Util::DirCopy qw(dircopy);

sub new {
    my ($class, $opts) = @_;
    my ($self);

    $self = {
	depot => $opts->{depot},
	source => $opts->{source},
	target => $opts->{target}
    };

    bless $self, $class;
    
    return $self;
}

sub syncFromLocalCopy {
    my ($self) = @_;

    dircopy($self->{source}, $self->{target});
}

sub syncFromP4 {
    my ($self) = @_;

    my $p4 = new Util::Perforce;
    my $spec = {
	root => $self->{target},
	view => {
	    $self->{depot} => "..."
	}
    };
    my $client = $p4->newClient($spec);
    $p4->syncLatestRevisions($client);
    $p4->deleteClient($client);
}

sub sync {
    my ($self) = @_;

    if (length($self->{source}) != 0 && -d $self->{source}) {
	$self->syncFromLocalCopy;
    } else {
	$self->syncFromP4;
    }
}

sub start {
    my ($self) = @_;

    $self->sync();

    # setup environment variables
    $ENV{'PATH'} = $self->{target}.";".$ENV{'PATH'};
    $ENV{'BUNDLE_BUILD_VER'} = "RC";

    # start a dos command window
    system('start "EDW BundleBuild (RC)"');
}

1;
