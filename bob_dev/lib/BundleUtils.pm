package BundleUtils;
use strict;
use Tie::File;
use Switch;
use LWP::UserAgent;
use LWP::Simple;
use XML::XPath;
use Crypt::CBC;
use MIME::Base64;
use Data::Dumper;

###########################################################################
#  
# Author      : Awen zhu
# CreateDate  : 2012-5-21
# Description : Database Common functions
# ChangeHist  : 2012-5-21 Init checkin.
#
# Depedencies :
#               
#				
#				
###########################################################################

sub new
{
	my $class = shift;
	my $self = { };
	bless $self;
	$self->{"logFile"} = shift;	
	$self->{"isDebug"} = shift;
	$self->{"isOverWrite"} = shift;
	return $self;
}

sub _set
{
	my $self = shift;
	my $name = shift;
	my $value = shift;
	$self->{$name} = $value;
}

# format date time functions, 
sub fdt
{
	my $self = shift;
	my $dtmask = shift;
	my @dt = localtime;
	my $ft;
	my $dth;
	$dtmask = 'yyyy-mm-dd hh24:mi:ss' if not defined($dtmask);
	$dth->{ddd} = $dt[7]; # day of year 1-366
	$dth->{day} = $dt[6]; # week day 0-6
	$dth->{yyyy} = sprintf("%4d",$dt[5]+1900); # 4-digit year
	$dth->{yy} = substr($dth->{yyyy},2,2); # 2-digit year
	$dth->{mm} = sprintf("%2.2d",++$dt[4]); # 2-digit month 1 - 12
	switch ($dth->{mm})
	{
		case /01/ { $dth->{mon} = 'Jan.'; $dth->{month} = 'January'; }
		case /02/ { $dth->{mon} = 'Feb.'; $dth->{month} = 'February'; }
		case /03/ { $dth->{mon} = 'Mar.'; $dth->{month} = 'March'; }
		case /04/ { $dth->{mon} = 'Apr.'; $dth->{month} = 'April'; }
		case /05/ { $dth->{mon} = 'May.'; $dth->{month} = 'May'; }
		case /06/ { $dth->{mon} = 'Jun.'; $dth->{month} = 'June'; }
		case /07/ { $dth->{mon} = 'Jul.'; $dth->{month} = 'July'; }
		case /08/ { $dth->{mon} = 'Aug.'; $dth->{month} = 'August'; }
		case /09/ { $dth->{mon} = 'Sep.'; $dth->{month} = 'September'; }
		case /10/ { $dth->{mon} = 'Oct.'; $dth->{month} = 'October'; }
		case /11/ { $dth->{mon} = 'Nov.'; $dth->{month} = 'November'; }
		case /12/ { $dth->{mon} = 'Dec.'; $dth->{month} = 'December'; }
	}
	$dth->{dd} = sprintf("%2.2d",$dt[3]); # day of month 1-31
	$dth->{hh24} = sprintf("%2.2d",$dt[2]); # hour of day 0-23
	$dth->{hh} = sprintf("%2.2d",$dth->{hh24}==0?0:$dth->{hh24} - 12); # hour of day 1-12
	$dth->{h} = $dth->{hh24}==0?0:$dth->{hh24} - 12; # hour of day 1-12
	$dth->{mi} = sprintf("%2.2d",$dt[1]); # Minute 0 - 59
	$dth->{ss} = sprintf("%2.2d",$dt[0]); # second 0 - 59
	my @datemark = ('yyyy','yy','mm','month','mon','day','ddd','dd','hh24','hh','h','mi','ss'); # dont change the element's order of array
	for(@datemark)
	{		
		$dtmask =~ s/$_/$dth->{$_}/i;
	}
	return $dtmask;
}

sub debug{
   my $self = shift;
   my $msg = shift;
   if ($^W) {
      print "debug => $0 : $msg\n";
   }
}

sub _log{
	my $self = shift;
	my $msg = shift;
	my $timestamp = shift;
	my $logfile = $self->{"logFile"};
	my ($dtmask,$ts);
	$dtmask = $1 if $logfile =~ /_(.*?)\./i;
	$ts = $self->fdt($dtmask);
	$logfile =~ s/$dtmask/$ts/i;
	my @lines;
	tie @lines, 'Tie::File', $logfile, discipline => ':encoding(UTF8)' or die "Could not open file with $!";
	if ($timestamp != 1)
	{
		push @lines, fdt()." :- $msg";
	} else { push @lines,$msg; }
	untie @lines;
}

sub _logclean
{
	my $self = shift;
	my @lines;
	tie @lines, 'Tie::File', $self->{"logFile"} or die "Could not open file with $!";
	$#lines -= @lines if ($self->{"isOverWrite"});
	untie @lines;
}

sub arrayref2array
{
	my $self = shift;
	my $ar = shift;
	my @a;
	foreach my $item ( @{$ar} ) {   
		push @a,$item;
	}
	return @a;	
}

sub textArea2array
{
	my $self = shift;
	my $str = shift;
	my (@a,@b);
	@a = split "\n",$str;
	for(@a)
	{
		if (/\S/) #remove blank lines
		{
			$_ =~ s/^\s+//; #remove blank of beginning
			push @b,$_;
		}
	}
	return @b;
}

sub readfile{
	my $self = shift;
	my $file = shift;
	my @arr;
	my $f = tie @arr, "Tie::File", $file;
	untie @arr;
	return @arr;
}




sub getDB2StmtTerm
{
	my $self = shift;
	my $db2script = shift;
	my @stmt = $self->readfile($db2script);
	my $term = ";"; # default terminator is ";"
	for (@stmt)
	{	
		$term = $1 and last if $_ =~ /\s*--#\s*set\s*terminator(.*?)$/i;
	}
	$term =~ s/^\s+//;
	$term =~ s/\s+$//;
	return $term;
}

sub uniq{
my $self = shift;
my %seen = ();
return grep { ! $seen{ $_ }++ } @_;
}


sub encrypt
{
	my $self = shift;
	my $string = shift;
	my $key = substr(shift,0,8);
	my $iv = substr(shift,0,8);
	my $cipher = Crypt::CBC->new(
		-key    => length($key)==8 ? $key : ( $key.'!' x ( 8 - length($key) ) ),
		-cipher => 'Blowfish',
		-header => 'none',
		-iv     => length($iv)==8 ? $iv : ( $iv.'!' x ( 8 - length($iv) ) ),
	);	
	return encode_base64($cipher->encrypt($string));	
}

sub decrypt
{
	my $self = shift;
	my $string = shift;
	my $key = substr(shift,0,8);
	my $iv = substr(shift,0,8);
	my $cipher = Crypt::CBC->new(
		-key    => length($key)==8 ? $key : ( $key.'!' x ( 8 - length($key) ) ),
		-cipher => 'Blowfish',
		-header => 'none',
		-iv     => length($iv)==8 ? $iv : ( $iv.'!' x ( 8 - length($iv) ) ),
	);
	return $cipher->decrypt(decode_base64($string));	
}
1;