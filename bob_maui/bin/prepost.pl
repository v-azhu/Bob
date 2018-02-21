###########################################################################
#  
# Author      : Awen zhu
# CreateDate  : 2012-3-27
# Description : Automatic of Pre/Post deployment, Extracts XML content from raid.txt 
#				files and execute them accordingly.
# ChangeHist  : 2012-3-27 Init checkin.
#
# Depedencies : 
#               
#				
#				
###########################################################################
use lib 'd:\bob\lib';
use strict;
use XML::XPath;
use DBI; 
use Tie::File;
use Switch;
use File::Find::Rule;
use File::Basename;
use DBComm;
use BundleUtils;
use Data::Dumper;

my $seq = shift;
my $dir = shift;
my $logfile = "..\\..\\release\\ApplyBundledHotfixes_LOG\\ManualStep_".$ENV{ENV}.".log";
#my $logfile = "log.txt";

#my $EDWBuild = DBComm->new($logfile,{"isOverWrite"}=>1);
my $EDWBuild = DBComm->new($logfile);
#$EDWBuild->_logclean; #clear up log file

my $ENV = $ENV{ENV};
my ($XMLRaw,$XP);
my (@ordNums,@NS,@fs,@raidfiles);
my ($target,$type,$host,$username,$continue,$cmd,$fromdir,$todir,$f,$src,$tgt,$server,$database,$DBH);
my $raid;


#################### Main process ########################
my @raidfiles = File::Find::Rule->file()->name("raid*.txt")->in($dir."\\RaidFiles");
foreach my $raidfile(@raidfiles)
{

	$raid = basename($raidfile);
	$raid =~ s/[^0-9]//g;
	$XMLRaw = xmlExtracter($raidfile);
	$EDWBuild->_log("*********** $seq manual steps of $raid ***********\n\n ") if defined($XMLRaw);
	next if not defined($XMLRaw);
	$XP = XML::XPath->new( xml => $XMLRaw );
	@ordNums = sort{ $a<=>$b } (getOrdNum($seq,$XP));

	foreach my $ordNum(@ordNums)
	{
		@NS = $XP->find("//*[\@ordnum='$ordNum']")->get_nodelist;
		$target   = $NS[0]->getAttribute("target");
		$type     = $NS[0]->getAttribute("type");
		$server   = $NS[0]->getAttribute("server");
		$database = $NS[0]->getAttribute("database");
		$username = $NS[0]->getAttribute("username");
		$continue = $NS[0]->getAttribute("continueOnFailure");
		$cmd      = $NS[0]->string_value;
		$fromdir  = $NS[0]->getAttribute("fromdir");
		$todir    = $NS[0]->getAttribute("todir");
		$continue = $NS[0]->getAttribute("continueOnFailure");
		$host     = getHost($ENV,$type);
		
		if ( $type =~ /ebs02|nrt/i )
		{
			$DBH = $EDWBuild->conn('SQL',$host,$database,'','');
		} elsif ( lc($type) eq lc('db2') )
		{
			$DBH = $EDWBuild->conn('db2','',$host,$ENV{DB2_User},$ENV{DB2_Pass});
		}
		
		if ($NS[0]->getName =~ /exec/i) # Linux cmd execution
		{
			if ($ENV =~ /$target/i)
			{
				$EDWBuild->_log("start executing command, OrdNum = $ordNum");
				sshRemoteExec($cmd,$host,$username,$continue);
			} else { $EDWBuild->_log("Ignore this step\( $cmd \) in $ENV since target specified as $target only\n"); }
		} elsif ($NS[0]->getName =~ /copy/i) # File copy
		{
			@fs = $NS[0]->getChildNodes;

			if ($ENV =~ /$target/i)
			{
				foreach my $fs(@fs)
				{
					$f = $fs->string_value;
					if ($f !~ /^\s*$/)
					{
						$src = $fromdir.($type=~/win/i ? "\\" : "\/").$f;
						$EDWBuild->_log("starting copy files to $host:$todir, OrdNum = $ordNum");
						fileTransfer($src,$username,$host,$todir,$type,$continue);
					}
				}
			} else { $EDWBuild->_log("Ignore this step\( copy files from:$fromdir to:$todir \) in $ENV since target specified as $target only\n"); }
		} elsif ($NS[0]->getName =~ /pmcmd/i) # informatica cmd execution
		{

			if ($ENV =~ /$target/i)
			{
				$EDWBuild->_log("start executing command, OrdNum = $ordNum");
				pmcmdExec($cmd,$continue);
			} else { $EDWBuild->_log("Ignore this step\( $cmd \) in $ENV since target specified as $target only\n"); }
		} elsif ($NS[0]->getName =~ /dbstmts/i) # sql statments execution
		{
			if ($ENV =~ /$target/i)
			{
				$EDWBuild->_log("start executing sql statment, OrdNum = $ordNum");
				my @stmts = $EDWBuild->textArea2array($cmd);
				for (@stmts)
				{
					$EDWBuild->execSQL($DBH,$_,1);
				}
				$EDWBuild->disconn($DBH);
			} else { $EDWBuild->_log("Ignore this step\( $cmd \) in $ENV since target specified as $target only\n"); }
		} elsif ($NS[0]->getName =~ /dbscriptfiles/i) # database script file execution
		{
			if ($ENV =~ /$target/i)
			{
				$EDWBuild->_log("start applying database script file, OrdNum = $ordNum");
				my @files = $EDWBuild->textArea2array($cmd);
				foreach my $file (@files)
				{
					if ( uc($type) eq 'DB2' )
					{
						if ( $EDWBuild->db2cmd($file) == 0 )
						{
							$EDWBuild->_log("The database script $file applied successfully!\n");
						} else { $EDWBuild->_log("An error occured during applying database script [ $file ]\n"); }
					}
				}
			} else { $EDWBuild->_log("Ignore this step\( $cmd \) in $ENV since target specified as $target only\n"); }
		}
		
	#clearup variables
	reset 'a-z';
	}
	$EDWBuild->_log("******** End of $seq Manual Step of $raid ********\n\n ",$logfile) if defined($XMLRaw);
}



################################################

# We always assuming that a ssh-key generated and in the right place. it also depends on Cygwin's configration.
sub sshRemoteExec
{
	my $cmd = shift;
	my $tgt = shift;
	my $user = shift;
	my $c = shift;
	my $rs;	
	$rs = `ssh $user\@$tgt '$cmd'`;
	$EDWBuild->_log("$cmd\n$rs\n\nExitCode:\n------\n $? \n");

	exit($?) if (($? != 0) and ($c eq "N"));
	return $?;
}

sub fileTransfer
{
	my $src = shift;
	my $user = shift;
	my $host = shift;
	my $tgt = shift;
	my $type = shift;
	my $c = shift;
	my $rs;
	if ($type =~ /win/i)
	{
		$rs = qq/xcopy \/R \/Y $src $tgt/; # call xcopy to copy file if window type of OS.
	} else {
		$src = `cygpath $src`; # convert dos style path to unix likely.
		$rs = qq/scp -r $src $user\@$host\:$tgt/; # call scp to copy file if linux type of OS.
	}
	$EDWBuild->_log("$rs".`$rs`."\n\nExitCode:\n------\n $? \n");
	exit($?) if (($? != 0) and ($c eq "N"));
	return $?;
}

sub pmcmdExec
{
	my $cmd = shift;
	my $c = shift;
	my $rs;	
	$cmd =~ s/^\s+|\s+$//g;
	$rs = `$cmd`;
	$EDWBuild->_log("$cmd\n$rs\n\nExitCode:\n------\n $? \n");
	if ($? == 768 and $cmd =~ /waitworkflow/i) #ExitCode=768 means workflow not running at all, It's good to go
	{
		return $?;
	}
	elsif (($? != 0) and ($c eq "N"))
	{
		exit($?);
	}
	return $?;
}

sub LZBOverrideUpd
{
	my $env = $ENV{ENV};
	my $pf = '/ExternalDataFeed/ETL/LZ_Business_Override.txt'; # this is default path of LZ_Business_Override.txt
	# get parameter files from target server and put it into current dir.
	my $host = getHost($env,'Infanux');
	`scp -r infadm@$host:$pf .`;
	#change parameters 
	my $start = '\[s_LZ_ATLAS_Generate_Run_ID\]';
	my $end = '\[';

	my @grabbed;
	while (<DATA>) {
		if (/$start/) {
			push @grabbed, $_;
			while (<DATA>) {
				s/\$\$BUSINESS_DATE_START=/\$\$BUSINESS_DATE_START=20120809/i;
				s/\$\$BUSINESS_DATE_END=/\$\$BUSINESS_DATE_END=20120814/i;
				last if /$end/;
				push @grabbed, $_;
			}
		}
	}

	print @grabbed;
	
	# put back parameter file to target server
	
	
}

sub xmlExtracter {
	my $filename = shift;
	my $start = qr/<\?xml version="1.0"\?>/; # This is pattern to identify where XML content start, 
	my $end = qr/<\/build>/;
	my $XMLRaw;
	if(open(FILE, $filename)) { #open raid.txt and extracting XML part
		while (<FILE>)
		{
			if (/$start/../$end/)
			{
				$XMLRaw = $XMLRaw.$_;
			}
			last if /$end/;
		}
	}
	close(FILE);
	return undef($XMLRaw) if length($XMLRaw) == 0;
	# replace variable with value in the XML content since we allow var defined in the xml content
	my $XP = XML::XPath->new( xml => $XMLRaw );
	my @nodes = $XP->find("/build/property/var")->get_nodelist;
	my ($var,$val);
	foreach my $node (@nodes) {
		$var = $node->getAttribute("name");
		$val = $node->getAttribute("value");
		$XMLRaw =~ s/\{$var\}/$val/gi;
	}
return $XMLRaw;
}

# get all order number of XML content
sub getOrdNum
{
	my $n = shift;
	my $XP = shift;
	my @NS = $XP->find("/build/$n/*[\@ordnum]")->get_nodelist;
	my @values;
	foreach my $n (@NS) {
		 push(@values, $n->getAttribute("ordnum"));
	}
	return @values; 
}

# Host map, Return Host name by ENV and type, 
sub getHost
{
	my $ENV = shift;
	my $type = shift;
	my $DB2MapRef = {'DEV'=>'DEVEDW','TEST'=>'TESTEDW','RC'=>'RCEDW','MLN'=>'MLNEDW','PROD'=>'PRODEDW'};
	my $InfaMapRef = {'DEV'=>'cheletledw001','TEST'=>'cheletledw011','RC'=>'cheletledw021','MLN'=>'cheletledw201','PROD'=>'che-etledw05'};
	my $HadoopMapRef = {'DEV'=>'chelhdcledw001','TEST'=>'chelhdcledw002','RC'=>undef,'MLN'=>undef,'PROD'=>'phsxedwhdc001'};
	my $OminMapRef = {'DEV'=>'CHELOMNEDW001','TEST'=>'CHELOMNEDW002','RC'=>undef,'MLN'=>undef,'PROD'=>'CHE-OMNEDW001'};
	my $EBS02MapRef = {'DEV'=>'BLSQLDOMDV01','TEST'=>'BLSQLDMOHF02','RC'=>'CHELSQLDW01','MLN'=>'CHELSQLDW201','PROD'=>'CHE-SQLDW02'};
	my $GuardianMapRef = {'DEV'=>undef,'TEST'=>undef,'RC'=>'chelgwsedw003','MLN'=>'chelgwsedw201','PROD'=>'che-utldws03'};
	my $DasMapRef = {'DEV'=>'chelomsedw002','TEST'=>'chelomsedw001','RC'=>'cheljvcedw051','MLN'=>'cheljvcedw201','PROD'=>'phexjvcedw001'};
	switch($type)
	{
		case /Infanux/i { return $InfaMapRef->{$ENV}; }
		case /Hadoopunx/i { return $HadoopMapRef->{$ENV}; }
		case /Omniunx/i { return $OminMapRef->{$ENV}; }
		case /ebs02/i { return $EBS02MapRef->{$ENV}; }
		case /db2/i { return $DB2MapRef->{$ENV}; }
		else { return -1; }
	}

}
