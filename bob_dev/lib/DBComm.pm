package DBComm;
@ISA = qw(BundleUtils);

use strict;
use DBI;
use Text::Table;
use Tie::File;
use Switch;
use Cwd qw/abs_path/;
use File::Basename;

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
	my $self = BundleUtils->new(@_);
	bless $self, $class;
	return $self;
}

sub retrivedata2textbl
{   
	my $self = shift;
	my $dbh = shift;
	my $sql = shift;
	my $sth = $self->execSQL($dbh,$sql);
	my $colname = $sth->{NAME};
	my @rs;
	my $t = Text::Table->new($self->arrayref2array($colname));
	$t->add(' '); #add a new blank row
	while(@rs = $sth->fetchrow_array())
	{
	  $t->add(@rs);
	}
	$self->_log($t) if defined($colname);
	return $t;
}

sub execSQL
{
  my $self = shift;
  my $dbh = shift;
  my $sql = shift;
  my $isLog = shift;
  my $sth = $dbh->prepare($sql);
  my $rc = $sth->execute();
  if ($isLog == 1)
  {
	  if ($sth->err)
	  { $self->_log($sql."\n".$sth->errstr); } 
	  else 
	  { 
		if ($sql =~ /^select/i)
		{
			my @cols = $self->arrayref2array($sth->{NAME});
			$self->_log("$sql\n@cols\n");
			while(my @resultset = $sth->fetchrow_array())
			{
				$self->_log("@resultset",1);
			}
				$self->_log("data fetched!\n");
		}
		elsif ($sql =~ /update|delete|insert/i)
		{
			$self->_log(substr($sql,1,200)."\n"." "x23 . $sth->rows." [rows effected]\n");
		} else
		{
			$self->_log("$sql\n"." "x23 . "The statment applied successfully!\n");
		}
	  }
	  return $?;
  } else { return $sth };
} 

sub conn
{
  my $self = shift;
  my ($ctype,$server,$db,$uname,$passwd) = @_;
  my $connstr;
  my $DBHandle;
  
  switch($ctype)
  {
	  case /DB2/i { $connstr = "dbi:DB2:$db"; }
	  case /SQL/i { $connstr = "dbi:ODBC:Driver=SQL Server;Server=$server;database=$db"; }
	  case /MYSQL/i { exit($self->_log("Not supported yet!")); }
	  case /ORACLE/i { exit($self->_log("Not supported yet!")); }
	  else { exit($self->_log("What kind of database will you connect to?")); }
  }
  # Sql server with trusted connection, put username and password as blank
  $DBHandle = DBI->connect($connstr, $uname, $passwd,{PrintError=>1,RaiseError=>1}) || die ($self->_log("Can't connect to $db: $DBI::errstr"));
 return $DBHandle;
}

sub disconn
{
  my $self = shift;
  my $dbh = shift;
  my $sth = shift;
  my $handles = $dbh->{ActiveKids};
  for (my $i = 0; $i < $handles; $i++)
  {
     if($i == 0)
     {
       $sth->finish;
     }
     else
     {
       my $h = "\$sth$i"; 
       eval "$h->finish";
     }
  }
  $dbh->disconnect();
}

sub db2cmd
{
	my $self = shift;
	my $s = shift;
	my $lp = abs_path($s);
	$lp =~ s/BusinessSystems(.*+)//i;
	$lp .= "BusinessSystems/Common/DBBuild/db/release/ApplyBundledHotfixes_LOG/".basename($s).".output.txt";
	$ENV{'DB2CLP'}='**$$**' if (!$ENV{DB2CLP});
	my @stmt = $self->readfile($s);
	my $term = $self->getDB2StmtTerm($s);
	my $rc = open(DB2CMD, "|db2 -tvs >$lp"); # option s make sure stop execution on command error
    return -1 unless ($rc);
    print DB2CMD <<SQLFILEEOF;
	-- create connection
	-----------------------------------------------------------------
	connect to $ENV{ENV}EDW user $ENV{DB2_User} using $ENV{DB2_Pass};
	-----------------------------------------------------------------
	@stmt
	-- reset connection
	-----------------------------------------------------------------
	connect reset$term
	terminate$term
	-----------------------------------------------------------------	
SQLFILEEOF
	close(DB2CMD);
	print "ExitCode\n---------\n$?";
	#######################################################################
	# handle with exit code
	#	Return Code				-s Option Set			+s Option Set
	#	0 (success)				execution continues		execution continues
	#	1 (0 rows selected)		execution continues		execution continues
	#	2 (warning)				execution continues		execution continues
	#	4 (DB2 or SQL error)	execution stops			execution continues
	#	8 (System error)		execution stops			execution stops
	#######################################################################
	return $?;
}

sub sqlcmd
{
	my $self = shift;
	my $server = shift;
	my $db = shift;
	my $infile = shift;
	my $outfile = $infile.".out";
	# We alwasy asumming that it is a trusted connection. 
	my $sqlcmd = "sqlcmd -S $server -d $db -E -i $infile -o $outfile";
	system($sqlcmd);
	$self->_log("$sqlcmd\n\nExitCode\n------\n$?");
	return $?
}


sub mysqlcmd
{

}

sub oraclecmd
{

}

1;