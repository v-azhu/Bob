use strict;
use lib '../lib';
use BundleComm;
use Data::Dumper;
use POSIX;
use File::Find::Rule;
use Tie::File;

###########################################################################
#  
# Author      : Awen zhu
# CreateDate  : 2012-6-30
# Description : Email build system, Main process.
# ChangeHist  : 2012-6-30 Init checkin.
#
# Depedencies :
#               
#				
#				
###########################################################################

my $XConfig  = "../conf/XConfig.xml";
my $BC = BundleComm->new($XConfig);
$BC->_set('LogFile',$BC->xget('/EDWEBS/Bundle/LogFile/node()'));
$BC->_set('CntlFile',$BC->xget('/EDWEBS/Bundle/CntlFile/node()'));
my $BU = BundleUtils->new($BC->xget('/EDWEBS/Bundle/LogFile/node()'));
my $ActiveQueue = $BC->_init();
$BU->_log("restored requests from control file:");
$BU->_log( Dumper $ActiveQueue );
my @AQKeys;
my ($Reqs,$MsgRef);
my $uptime=$BU->fdt('yyyy-mm-dd hh24:mi:ss');
my $downtime;
my $err;
my $PWDExpireDate='20880101';
$|=1;

$SIG{__DIE__} = sub { $err = shift; die($BU->_log("[ Error ] : $err")) if $err !~ /Fcntl macro F_GETFL/i;};

END { 
#send out alert email to info this outage. 
$downtime=$BU->fdt('yyyy-mm-dd hh24:mi:ss');
$BC->alert($uptime,$downtime,$err);
#exec $0; # whatever how it died, restart it immediately, Not yet tested all siglas, but Ctrl-C or kill -9 can finishs it.
#create trigger file
if ( lc($ENV{computername}) eq lc($BC->xget('/EDWEBS/Cluster/Master/@Server')) )
{
	system("del /Q ".$BC->xget('/EDWEBS/Cluster/Master/@HeartBeatFile'));
	$BU->_log("Remove trigger file.");
}

} 

while (1)
{
	# appending new requests to active queue ...
	for (;;)
	{
		if (lc($ENV{computername}) eq lc($BC->xget('/EDWEBS/Cluster/Slave/@Server')))
		{
			next until $BC->_standby;
		}
		for (;;)
        {
            if ($BC->timeWindow)
            {
                last;
            } else
            {
                $BU->_log("Out of time window, Sleeping 30 sec...");
                sleep 30;
            }
        } 
		$Reqs = $BC->validation($BC->reqParser);
		$BU->_log("Adding new requests into the queue:\n".Dumper $Reqs) if keys %$Reqs;
		$ActiveQueue = {%$ActiveQueue,%$Reqs};
		@AQKeys = grep !/MQCount/i, keys %$ActiveQueue;
		# break loop if there is no new requests or current queue has configed MaxItem
		last if ($#AQKeys + 1 == $BC->xget('/EDWEBS/Bundle/MaxItem/node()') or ! keys %$Reqs );
	} 
	$ActiveQueue->{MQCount} = $#AQKeys + 1;
	# For each item of active queue, launch for deployment but ignore one which is already running ...
	if (defined($ActiveQueue))
	{
		$BU->_log("Requests queue is as follows:\n".Dumper $ActiveQueue) if ( $ActiveQueue->{MQCount} > 0 );
		foreach my $AQKey(@AQKeys)
		{
			if ( $ActiveQueue->{$AQKey}->{BundleStatus} ne 'Running' )
			{
				$BU->_log("Create control message for $AQKey => raids :".$ActiveQueue->{$AQKey}->{Subject}->{raids});
				$BC->msgCleanUp($AQKey);
				$BC->msgTable($AQKey);				
				$BC->sendMsg($AQKey,'Raids',$ActiveQueue->{$AQKey}->{Subject}->{raids});
				$BC->sendMsg($AQKey,'From',$ActiveQueue->{$AQKey}->{From});
				$BC->sendMsg($AQKey,'To',$ActiveQueue->{$AQKey}->{To});
				$BC->sendMsg($AQKey,'Cc',$ActiveQueue->{$AQKey}->{Cc});
				$BC->sendMsg($AQKey,'BundleName',$ActiveQueue->{$AQKey}->{BundleName});
				$BC->sendMsg($AQKey,'ENV',$ActiveQueue->{$AQKey}->{Subject}->{ENV});
				$BC->sendMsg($AQKey,'ReceivedDate',$ActiveQueue->{$AQKey}->{ReceivedDate});
				$BC->sendMsg($AQKey,'BldStartDT',$BU->fdt());
				$BC->sendMsg($AQKey,'Stage',$ActiveQueue->{$AQKey}->{Subject}->{Stage});
				$BU->bundlebuildAutoUpd(); # BundleBuild auto update
				$BC->reqResponser($ActiveQueue->{$AQKey}->{From},$AQKey,$ActiveQueue->{$AQKey}->{BundleName}); # sending response email to user before deployment
				if ( lc($ActiveQueue->{$AQKey}->{Subject}->{Stage}) ne "only" )
				{
					#print $BU->fdt()." : starting deployment raid".$ActiveQueue->{$AQKey}->{Subject}->{raids}." on ".$ActiveQueue->{$AQKey}->{Subject}->{ENV}."\n";
					my $cmd = "start antins ".$AQKey;
					   $cmd .= " ".$ActiveQueue->{$AQKey}->{BundleName};
					   $cmd .= " ".$ActiveQueue->{$AQKey}->{Subject}->{raids};
					   $cmd .= " ".$ActiveQueue->{$AQKey}->{Subject}->{ENV};
					   $cmd .= " ".$ActiveQueue->{$AQKey}->{Subject}->{RaidsType};
					   $cmd .= " \"".$ActiveQueue->{$AQKey}->{Subject}->{InfaUser}."\"" if ($ActiveQueue->{$AQKey}->{Subject}->{ENV} =~ /dev/i and defined($ActiveQueue->{$AQKey}->{Subject}->{InfaUser}));
					   $cmd .= " \"".$ActiveQueue->{$AQKey}->{Subject}->{InfaPass}."\"" if ($ActiveQueue->{$AQKey}->{Subject}->{ENV} =~ /dev/i and defined($ActiveQueue->{$AQKey}->{Subject}->{InfaPass}));
					$BU->_log($cmd);
					system($cmd);
					$BC->sendMsg($AQKey,'PID',$BC->getPID($ActiveQueue->{$AQKey}->{BundleName}));
					# Mark bundle as running
					$ActiveQueue->{$AQKey}->{BundleStatus}='Running';
					# wait until bundle created then move to next raid
					sleep 3 until ( length($BC->getMsg($AQKey)->{CreateBundle}) > 0 );
					undef $cmd;
				} else 
				{
					$BC->sendMsg($AQKey,'CreateBundle','Succeed');
					$BC->sendMsg($AQKey,'Status','Succeed');
				}
			}
	    }
		# waiting for completion process
		while (1)
		{
			sleep 10;
			$BU->_log("Sleeping 10 seconds and waiting for build requests [ @AQKeys ] to be completed.") if ( $ActiveQueue->{MQCount} > 0 );
			for ( my $idx=0; $idx<=$#AQKeys; $idx++ )
			{
				# Terminate long running bundle after defined x minutes
				$ActiveQueue->{$AQKeys[$idx]}->{'LongRunningTasks'} = $BC->longRunningBundleTerminate($AQKeys[$idx]);
 			    $MsgRef = $BC->getMsg($AQKeys[$idx]);
				if ($MsgRef->{CreateBundle} =~ /Failed/)
				{
					$BC->sendMail($AQKeys[$idx],$ActiveQueue->{$AQKeys[$idx]});
					$BU->_log("Create bundle failed for request msg ".$AQKeys[$idx]);
					$BC->msgCleanUp($AQKeys[$idx]);
					delete $ActiveQueue->{$AQKeys[$idx]};
					$ActiveQueue->{MQCount}--;
					splice(@AQKeys,$idx,1);
				}
				if ( length($MsgRef->{Status}) > 0 )
				{
					if ( lc($ActiveQueue->{$AQKeys[$idx]}->{Subject}->{Stage}) ne "only" )
					{
						#$BC->scpProcDir($ActiveQueue->{$AQKeys[$idx]}->{BundleName},$ActiveQueue->{$AQKeys[$idx]}->{Subject}->{ENV});
						$BC->bLogger($AQKeys[$idx],$ActiveQueue->{$AQKeys[$idx]}->{BundleName}); 
					}
					#Stage bundle
					if ( uc($ActiveQueue->{$AQKeys[$idx]}->{Subject}->{ENV}) eq "MLN" and length($ActiveQueue->{$AQKeys[$idx]}->{Subject}->{Stage}) > 0)
					{
						$ActiveQueue->{$AQKeys[$idx]}->{StageOutput} = $BC->stageBundle($ActiveQueue->{$AQKeys[$idx]},$MsgRef->{Status});
					}
					# Integrate raids whatever deployment succeesfully or not.
					if (uc($ActiveQueue->{$AQKeys[$idx]}->{Subject}->{ENV}) eq "RC" and uc($ActiveQueue->{$AQKeys[$idx]}->{Subject}->{Integrate}) eq "YES")
					{
						$ActiveQueue->{$AQKeys[$idx]}->{ErrorCode} = $BC->Integrate($ActiveQueue->{$AQKeys[$idx]}->{Subject}->{raids});
					}
					$BC->sendMail($AQKeys[$idx],$ActiveQueue->{$AQKeys[$idx]});
					$BU->_log("Bundle compete with status ".$MsgRef->{Status}." request msg ".$AQKeys[$idx]);
					#print $BU->fdt() . " : " .$ActiveQueue->{$AQKeys[$idx]}->{Subject}->{raids}." Done with ".$MsgRef->{Status}."\n";

					$BC->msgCleanUp($AQKeys[$idx]);
					delete $ActiveQueue->{$AQKeys[$idx]};
					$ActiveQueue->{MQCount}--;
					splice(@AQKeys,$idx,1);
				}
			}
			# request list handler.
			$BC->actionHandler;
			# break loop to check/add new requests into queue if current queue less than configed items.
			last if ( $#AQKeys < $BC->xget('/EDWEBS/Bundle/MaxItem/node()') - 1 ); 
		}
	}
	else {
		$BU->_log('No requestes in the queue, sleep for ['.$BC->xget('/EDWEBS/Bundle/SleepTime/node()').'] seconds ...');
	}
	$BU->_log("sleeping ".$BC->xget('/EDWEBS/Bundle/SleepTime/node()')." and recheck new one") if ( $ActiveQueue->{MQCount} > 0 );
	sleep $BC->xget('/EDWEBS/Bundle/SleepTime/node()');
	if ($BU->fdt('hhmi') > 700 and $BU->fdt('hhmi') < 800 )
	{
		$BC->bobLogArchive();
		$BC->rmBundleFiles();
	}  
    
    if ($PWDExpireDate != $BU->fdt('yyyymmdd'))
    {
        $BU->_log("Password expire check");
        #$PWDExpireDate=$BC->PWDExpire();
    }
}