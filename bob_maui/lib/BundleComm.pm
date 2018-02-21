package BundleComm;
###########################################################################
#  
# Author      : Awen zhu
# CreateDate  : 2012-06-21
# Description : Bundle Common functions
# ChangeHist  : 2012-06-21 Init checkin.
#				2013-01-05 Made changes so that Bob only accept subjects that 
#						   start "FW: [bld_req]" or "[bld_req]".
#						   Bob now accept raid range, For example, Raid=123~125
#						   means Raid=123:124:125
#				2013-01-22 Added parsing actions, Allows user to list their 
#						   requests as well as cancel their requests.
#               2014-07-25 98480 remove db2 bundle logs
# Depedencies : DBComm and BundleUtils.
#               
#				
#				
###########################################################################
use strict;
use lib '../lib';
use Tie::File;
use DBI;
use Mail::IMAPClient;
use MIME::Lite;
use XML::XPath;
use DBComm;
use BundleUtils;
use File::Find::Rule;
use File::Basename;
use Data::Dumper;
use Date::Manip;
use IO::Socket::SSL;
use Switch;

sub new
{
	my $class = shift;
	my $self = { };
	$self->{'XConfig'} = shift;
	$self->{'LogFile'} = shift;
	$self->{'CntlFile'} = shift;
	bless $self, $class;
	return $self;
}

sub _set
{
	my $self = shift;
	my $key = shift;
	my $value = shift;
	$self->{$key} = $value;
}


sub _init
{
# We should thinking about couple of situations here but to be easy, we just mark BundleStatus as "running" or leave it as blank.
# Acturally we need to thinking about more, But that leaving us hard situations. To be easy we just assuming that Bundle always be "running" or not
# started yet.
	my $self = shift;
	my $msg;
	my @msgs;
	my $AQ = {};
	tie @msgs,'Tie::File',$self->xget('/EDWEBS/Bundle/CntlFile/node()');
	for(@msgs)
	{
		if (m/(\d+)/g)
		{
			if ( $msg != $1 )
			{
				$msg = $1;
				$AQ->{$msg}->{Cc} = $self->getMsg($msg)->{Cc};
				$AQ->{$msg}->{ErrorCode} = 0;
				$AQ->{$msg}->{Subject}->{ErrorCode} = 0;
				$AQ->{$msg}->{Subject}->{raids} = $self->getMsg($msg)->{Raids};
				$AQ->{$msg}->{Subject}->{ENV} = $self->getMsg($msg)->{ENV};
				$AQ->{$msg}->{BundleName} = $self->getMsg($msg)->{BundleName};
				$AQ->{$msg}->{Stage} = $self->getMsg($msg)->{Stage};
				$AQ->{$msg}->{ReceivedDate} = $self->getMsg($msg)->{ReceivedDate};
				$AQ->{$msg}->{To} = $self->getMsg($msg)->{To};
				$AQ->{$msg}->{From} = $self->getMsg($msg)->{From};
				$AQ->{$msg}->{BundleStatus} = ( $self->getMsg($msg)->{PID} > 0 ) ? 'Running' : ''; 
				$AQ->{MQCount}++;
			}
		}
	}
	untie @msgs;
	return $AQ;
}

sub _standby
{
	my $self = shift;
	my $triggerfile;
	
	if ( lc($ENV{computername}) eq lc($self->xget('/EDWEBS/Cluster/Slave/@Server')) and lc($self->xget('/EDWEBS/Cluster/Slave/@Enable')) eq "yes")
	{
		for (;;)
		{
			$triggerfile = "";
			$triggerfile = "\\\\".$self->xget('/EDWEBS/Cluster/Master/@Server')."\\";
			$triggerfile .= $self->xget('/EDWEBS/Cluster/Master/@BobHome');
			$triggerfile .= "\\bin\\".$self->xget('/EDWEBS/Cluster/Master/@HeartBeatFile');
			$triggerfile =~ s/\:/\$/i;
			if ( -f $triggerfile )
			{
				sleep 30;
			} else
			{
				return 1;
			}			
		}
	} else
	{
		system("type nul> ".$self->xget('/EDWEBS/Cluster/Master/@HeartBeatFile'));
	}
}

sub timeWindow
{
    my $self = shift;
    my $BU = BundleUtils->new($self->{'LogFile'});
    my $WeekDays = $self->xget('/EDWEBS/TimeWindow/WeekDays/text()');
    my $WeekDay = $BU->fdt('day');
    my $StartAt = $self->xget('/EDWEBS/TimeWindow/StartAt/text()');
    my $EndAt = $self->xget('/EDWEBS/TimeWindow/EndAt/text()');
    if ( $WeekDays =~ /$WeekDay/i and $BU->fdt('hh24mi') > $StartAt and $BU->fdt('hh24mi') < $EndAt )
    {
        return 1;
    } else { return 0; }
}

sub getPID
{
	my $self = shift;
	my $pattern = shift;
	my $cmd = "wmic process where(name='cmd.exe') get commandline,processid|grep -i $pattern|grep -v grep";
	my $out = `$cmd`;
	$out =~ s/\s//gi;
	return (defined($1)?$1:-1) if $out =~ /(\d+)$/;
}

sub taskkill
{
	my $self = shift;
	my $pid = shift;
	# terminate all given pid and its child processes.	
	my $o = `taskkill /PID $pid /T /F`;
	($? == 0) ? return $? : return $o;
}


# Extract value from XML by given xpath
sub xget
{
    my $self = shift;
	my $xpath = shift;
    my $xp = XML::XPath->new(filename => $self->{'XConfig'});
    if ( $xpath =~ /\@/i)
	{
		return $xp->find( $xpath );
	} else { return $xp->find ($xpath)->string_value; }
}

sub getAccountMap
{
	my $self = shift;
	my $env = uc(shift);
	my $BU = BundleUtils->new($self->{'LogFile'});
	my $envstr = "set env=$env\nset BO_User=".$self->xget("/EDWEBS/BuildAccountMap/$env/\@BOUser");
	$envstr .= "\nset BO_Pass=".$BU->decrypt($self->xget("/EDWEBS/BuildAccountMap/$env/\@BOPass"),$ENV{BobKey},$ENV{BobKey});
	$envstr .= "\nset DB2_User=".$self->xget("/EDWEBS/BuildAccountMap/$env/\@DB2User");
	$envstr .= "\nset DB2_Pass=".$BU->decrypt($self->xget("/EDWEBS/BuildAccountMap/$env/\@DB2Pass"),$ENV{BobKey},$ENV{BobKey});
	$envstr .= "\nset Infa_User=".$self->xget("/EDWEBS/BuildAccountMap/$env/\@InfaUser");
	$envstr .= "\nset Infa_Pass=".$BU->decrypt($self->xget("/EDWEBS/BuildAccountMap/$env/\@InfaPass"),$ENV{BobKey},$ENV{BobKey});
	$envstr .= "\nset CTM_User=".$self->xget("/EDWEBS/BuildAccountMap/$env/\@CTM_User");
	$envstr .= "\nset CTM_Pass=".$BU->decrypt($self->xget("/EDWEBS/BuildAccountMap/$env/\@CTM_Pass"),$ENV{BobKey},$ENV{BobKey});
	return $envstr;
}

sub checkPermission
{
	my $self = shift;
	my $user = shift;
	my $env  = shift;
    my $type = shift;
	my $rc;
	my $memberof;
	my $node;    
    my $BobHome = lc($ENV{computername}) eq lc($self->xget('/EDWEBS/Cluster/Slave/@BobHome')) ? $ENV{computername} : $self->xget('/EDWEBS/Cluster/Master/@BobHome');
 	my $BundleUtils = BundleUtils->new($self->{'LogFile'});
    my $retry;
    
	$user = $1 if $user =~ /<(.*?)\@/ig; #get user alias by given email address.
    my $cachefile = $BobHome.'\\cache\\'.$user;    
    my $mtime = (-M $cachefile);
    my $xp = XML::XPath->new(filename => $self->{'XConfig'});
	my @NS = $xp->find('/EDWEBS/PermissionMap/User')->get_nodelist;
    if ($mtime < 5 and (-e $cachefile))
    {   
        open FILE, $cachefile or die "Couldn't open file: $!";        
        $memberof = do { local $/; <FILE> };
        close FILE;
    } else { 
        my @lines;
        tie @lines, 'Tie::File', $cachefile or die "Could not open file with $!";
        $memberof = `dsquery user -samid "$user*"|dsget user -memberof -expand`;
        push @lines,$memberof;
        untie @lines;
    }

    foreach my $ns(@NS)
    {
        $node = $ns->string_value;
        if ( ( $ns->string_value =~ /$user/i or $memberof =~ /$node/gi ) and $ns->getAttribute("ENV") =~ /$env/i )
        {
            $rc = 0;
            last;
        } 
        else { 
            $rc = 'EDWEBS-00400' if $type eq 'Deploy';
            $rc = 'EDWEBS-00401' if $type eq 'ApplyAction';            
            $retry = 1;
        }
    }
    # is it posible to having LABEL controls redo process?
    if ($retry)
    {
        $BundleUtils->_log("Retry LDAP varify if cache varification fails.");
        my @lines;
        tie @lines, 'Tie::File', $cachefile or die "Could not open file with $!";
        $memberof = `dsquery user -samid "$user*"|dsget user -memberof -expand`;
        push @lines,$memberof;
        untie @lines;
        foreach my $ns(@NS)
        {
            $node = $ns->string_value;
            if ( ( $ns->string_value =~ /$user/i or $memberof =~ /$node/gi ) and $ns->getAttribute("ENV") =~ /$env/i )
            {
                $rc = 0;
                last;
            } 
            else { 
                $rc = 'EDWEBS-00400' if $type eq 'Deploy';
                $rc = 'EDWEBS-00401' if $type eq 'ApplyAction';
            }
        }
    }

    return $rc;
}

sub sendMail 
{
	my $self = shift;
	my $msg = shift;
	my $msgRef = shift;
	my $subject = 'Re:Build request for raids '.$msgRef->{Subject}->{raids};
	my $msgstatusRef = $self->getMsg($msg);
	my $from = $msgRef->{From};
	my $to = $msgRef->{To};
	my $cc = $msgRef->{Cc};
	my $bf = $msgRef->{BundleName};	
	my $stageot = $msgRef->{StageOutput};
	my $longRunningTasks = $msgRef->{LongRunningTasks};
	if ($msgRef->{ErrorCode} eq 0 and $msgRef->{Subject}->{ErrorCode} eq 0 )
	{
    	if ($msgstatusRef->{CreateBundle} =~ /Failed/i)
		{
			$msgRef->{ErrorCode} = 'EDWEBS-00200';
		} elsif ($msgstatusRef->{Status} =~ /Failed/i)
		{
			$msgRef->{ErrorCode} = 'EDWEBS-00000';
		} else
		{
			$msgRef->{ErrorCode} = 'EDWEBS-00000';
		}
	} elsif( length($msgRef->{Subject}->{ErrorCode}) > 1)
	{
		$msgRef->{ErrorCode} = $msgRef->{Subject}->{ErrorCode};
	}
	
	my $bodymsgcode = ($msgRef->{ErrorCode} eq 'EDWEBS-00000') ? 'EDWEBS-00000' : 'EDWEBS-00001';
	$bodymsgcode = 'EDWEBS-00002' if ( lc($msgstatusRef->{Stage}) eq "only" );
	#print "Stage=".$msgstatusRef->{Stage}."\nbodymsgcode=$bodymsgcode\n";
	my $body = $self->xget('/EDWEBS/Messages/msg[@code="'.$bodymsgcode.'"]');
	my $action = $self->xget('/EDWEBS/ErrorCodes/ErrorCode[@code="'.$msgRef->{ErrorCode}.'"]');
	$body =~ s/<--From-->/$from/gi;
	$body =~ s/<--ErrorCode-->/$msgRef->{ErrorCode}/gi;
	$body =~ s/<--Action-->/$action/gi;
	$body =~ s/<--Raids-->/$msgRef->{Subject}->{raids}/gi;
	$body =~ s/<--ENV-->/$msgRef->{Subject}->{ENV}/gi;
	$body =~ s/<--BuildStatus-->/$msgstatusRef->{Status}/gi;
	$body =~ s/<--ProcessID-->/$msgstatusRef->{ProcessID}/gi;
	$body =~ s/<!--LongRunningTasks-->/$longRunningTasks/gi;
	$body =~ s/<!--Stage-->/$stageot/gi;
    if ( $msgRef->{ErrorCode} eq 'EDWEBS-00200' )
    {
        $body =~ s/<!--RemoveComments//gi;
        $body =~ s/RemoveComments-->//gi;
        $body =~ s/&lt;/</gi;
        $body =~ s/&gt;/>/gi;
    }	
	$body =~ s/<--BundleFolder-->/$bf/gi;
	$body =~ s/<--computename-->/$ENV{COMPUTERNAME}/gi;
	
	my $BundleUtils = BundleUtils->new($self->{'LogFile'});
	my $smtp = $self->xget('/EDWEBS/SMTP/Server/text()');
	my $message = MIME::Lite->new(
		From    => 'edwbld@expedia.com',
		To      => $from.";".$to,
		Cc		=> $cc,
		Subject => $subject,
		Type    => 'multipart/mixed',
	);
	$message->attach(
		Type     => 'text/html',
		Data     => $body,
	);
	my @LogFiles = $self->logsFetcher($bf,1);
	if ($msgstatusRef->{Status} =~ /Failed/i)
	{
		for(@LogFiles)
		{
			$message->attach(
				Type     => 'text/plain',
				Path     => $_,
				Filename => basename($_),
				Disposition => 'attachment'		
			);
		}
	}
	$BundleUtils->_log("Send mail to : [ $to ] and Cc to : [ $cc ] for msg = $msg");
	$message->send('smtp',$smtp,debug=>1);
	return $?;
}

sub alert
{
	my $self  = shift;
	my $uptime = shift;
	my $downtime = shift;
	my $lasterr = shift;
	my $smtp = $self->xget('/EDWEBS/SMTP/Server/text()');
	my $body = $self->xget('/EDWEBS/Messages/msg[@code="EDWEBS-99998"]');
	my $message = MIME::Lite->new(
		From    => 'edwbld@expedia.com',
		To      => $self->xget('/EDWEBS/Alert/Reciever/text()'),
		Subject => '[ALERT] Bob died,please investigate!',
		Type    => 'multipart/mixed',
	);
	$body =~ s/<--uptime-->/$uptime/gi;
	$body =~ s/<--downtime-->/$downtime/gi;
	$body =~ s/<--lasterr-->/$lasterr/gi;
	$body =~ s/<--computename-->/$ENV{COMPUTERNAME}/gi;
	$message->attach(
		Type     => 'text/html',
		Data	 => $body,
	);
	$message->send('smtp',$smtp,debug=>1);
}

sub reqResponser
{
	my $self  = shift;
	my $to    = shift;
	my $msgid = shift;
	my $bn	  = shift;
	my $smtp = $self->xget('/EDWEBS/SMTP/Server/text()');
	my $body = $self->xget('/EDWEBS/Messages/msg[@code="EDWEBS-10000"]');
	my $message = MIME::Lite->new(
		From    => 'edwbld@expedia.com',
		To      => $to,
		Subject => '[EDWBuild] Your service number is '.$msgid,
		Type    => 'multipart/mixed',
	);
	$body =~ s/<--From-->/$to/gi;
	$body =~ s/<--BundleName-->/$bn/gi;	
	$body =~ s/<--msgid-->/$msgid/gi;	
	$body =~ s/<--computename-->/$ENV{COMPUTERNAME}/gi;
	$message->attach(
		Type     => 'text/html',
		Data	 => $body,
	);
	$message->send('smtp',$smtp,debug=>1);
}

sub reqList
{
	my $self = shift;
    my $aq = shift;
	my ($imap,$hmsg,$alias,$sbj,$rq);
	my $BU = BundleUtils->new($self->{'LogFile'});   
    $imap = $self->IMAPConnection;
	$imap->select($self->xget('/EDWEBS/IMAP/Folder/node()')) or die($BU->_log("Can not open folder with $@"));
	my @msg = $imap->unseen;
    $BU->_log ("Start adding requests to the hash ref.");
	foreach my $msg (@msg)
	{
		$hmsg = $imap->parse_headers($msg,"date","From","To","Cc","Subject","Message-ID");		
		$alias = $1 if $hmsg->{From}->[0] =~ /<(.*?)\@/ig;
		$hmsg->{Subject}->[0] =~ s/\s//gi;

		if ($hmsg->{Subject}->[0] =~ /^(\[|FW:\[)BLD_REQ\]:(.*?)raid=/i and $hmsg->{Subject}->[0] =~ /$aq->{ENV}/i )
		{
            $rq->{$msg}->{From} = $hmsg->{From}->[0];
			$rq->{$msg}->{To} = $hmsg->{To}->[0];
			$rq->{$msg}->{Cc} = $hmsg->{Cc}->[0];
			$rq->{$msg}->{ReceivedDate} = $hmsg->{date}->[0];
			$rq->{$msg}->{MsgType} = 'Inbox';
			$rq->{$msg}->{Raids} = $1 if ( $hmsg->{Subject}->[0] =~ /raid=(.*?)($|\|)/i );
			$rq->{$msg}->{ENV} = $1 if ( $hmsg->{Subject}->[0] =~ /env=(\w+)/i );
		} else { next; }
	}
	$imap->logout();
	# appeding request list from control file.
	for ( $self->getMsgIDbyEnv($aq->{ENV}) )
	{
		$rq->{$_} = $self->getMsg($_);
		$rq->{$_}->{MsgType} = 'CtrlFile';
        $rq->{$_}->{WhereItIs} = `wmic process where (ParentProcessId=$rq->{$_}->{PID}) get Caption,ProcessId,CommandLine`;
        $rq->{$_}->{WhereItIs} =~ s/ProcessId/ProcessId<br>/i;
        my $InfaPass=$BU->decrypt($self->xget("/EDWEBS/BuildAccountMap/$aq->{ENV}/\@InfaPass"),$ENV{BobKey},$ENV{BobKey});
        $rq->{$_}->{WhereItIs} =~ s/$InfaPass/******/i;        
        $rq->{$_}->{WhereItIs} = 'Completed' if length($rq->{$_}->{WhereItIs}) < 1;
    }
    $BU->_log ("Added Request list:".Dumper $rq);
    # print "Action responser";
	$self->actionResponser($aq,$rq);
}

sub actionResponser
{
    my $self = shift;
    my $aq = shift;
    my $rq = shift;
    my $body = "";
    my $tr;
    my $BU = BundleUtils->new($self->{'LogFile'});   
    if (lc($aq->{Action}) eq 'getreqlist')
    {
        $BU->_log ("Handling Action:-getReqList");
        $body = $self->xget('/EDWEBS/Messages/msg[@code="EDWEBS-00003"]');
        my $total=0;
        foreach my $rl ( keys %$rq )
		{
			$tr .= "<tr><td><font face=\"Verdana\" size=2>$rl</font>\n";
			$tr .= "<td><font face=\"Verdana\" size=2>".$rq->{$rl}->{Raids}."</font>";
			$tr .= "<td><font face=\"Verdana\" size=2>".$rq->{$rl}->{ENV}."</font>";
            $tr .= "<td><font face=\"Verdana\" size=2>".$rq->{$rl}->{From}."</font>";
            $tr .= "<td><font face=\"Verdana\" size=2>".$rq->{$rl}->{ReceivedDate}."</font>";
			$tr .= "<td><font face=\"Verdana\" size=2>".(($rq->{$rl}->{MsgType} eq 'CtrlFile')?$rq->{$rl}->{WhereItIs}:'Not Started Yet')."</font></tr>";
			$total++;
		}
		$tr .= 	"<tr><td colspan=\"6\"><font face=\"Verdana\" color=\"red\" size=2><b>Total : $total</b></font></td></tr>";
        $body =~ s/<--From-->/$aq->{From}/gi;
		$body =~ s/<!--ReqList-->/$tr/gi;
    } else
    {
       $BU->_log ("Not supported Action");
       $body = $self->xget('/EDWEBS/Messages/msg[@code="EDWEBS-00005"]');
       my $Desc = $self->xget('/EDWEBS/ErrorCodes/ErrorCode[@code="'.$aq->{ErrorCode}.'"]');
       $body =~ s/<--From-->/$aq->{From}/gi;
	   $body =~ s/<--act-->/$aq->{Action}/gi;
	   $body =~ s/<--ENV-->/$aq->{ENV}/gi;
	   $body =~ s/<--Ins-->/$aq->{Ins}/gi;
	   $body =~ s/<--ErrorCode-->/$aq->{ErrorCode}/gi;
       $body =~ s/<--Action-->/$Desc/gi;
    }
    my $message = MIME::Lite->new(
				From    => 'edwbld@expedia.com',
				To      => $aq->{From}.";".$aq->{To},
				Cc		=> $aq->{Cc},
				Subject => 'EDWBuild - Retrieve info from edwdeploy',
				Type    => 'multipart/mixed',
			);
    $message->attach(Type    => 'text/html',
					Data	 => $body,
					);
	$message->send('smtp',$self->xget('/EDWEBS/SMTP/Server/text()'),debug=>1);
    $BU->_log ("Sent feedback email to user");
}

sub actionHandler
{
    my $self = shift;
    my ($imap,$hmsg,$alias,$aq);
	my $BU = BundleUtils->new($self->{'LogFile'});
    my $pattern = lc($ENV{computername}) eq lc($self->xget('/EDWEBS/Cluster/Slave/@Server')) ? $self->xget('/EDWEBS/Cluster/Slave/@Partten') : $self->xget('/EDWEBS/Cluster/Master/@Partten');
    my $server = lc($ENV{computername}) eq lc($self->xget('/EDWEBS/Cluster/Slave/@Server')) ? $ENV{computername} : $self->xget('/EDWEBS/Cluster/Master/@Server');
    $server = uc($ENV{computername}) eq 'CHE-RDCEDW02' ? 'CHE-RDCEDW02' : $server;

    $imap = $self->IMAPConnection;
	$imap->select($server) or die($BU->_log("Can not open folder with $@"));
	my @msg = $imap->unseen;
    if (not defined(@msg))
    {
        $imap->logout();
        return;
    }    
    foreach my $msg (@msg)
    {
        $hmsg = $imap->parse_headers($msg,"date","From","To","Cc","Subject","Message-ID");		
		$alias = $1 if $hmsg->{From}->[0] =~ /<(.*?)\@/ig;
        my $sbj=$hmsg->{Subject}->[0];
        $sbj =~ s/\s//gi;
        if ( $sbj =~ /^(\[|FW:\[)BLD_REQ\]:(.*?)action=/i)
        {
            $BU->_log ("Start parsing action from folder : ".$server);
            $aq->{From} = $hmsg->{From}->[0];
            $aq->{To} = $hmsg->{To}->[0];
            $aq->{Cc} = $hmsg->{Cc}->[0];
            $aq->{ReceivedDate} = $hmsg->{date}->[0];
            $aq->{ENV} = $1 if ( $sbj =~ /env=(\w+)/i);
            
            if (not defined($aq->{ENV}))
            {
                $BU->_log ("ENV not given, error out");
                $aq->{ErrorCode} = 'EDWEBS-00402' 
            } else 
            {
                $aq->{Action} = $1 if ( $sbj =~ /Action=(\w+)/i);
                $aq->{Ins} =  $sbj =~ /Ins=(.*?)($|\|)/gi ? $1 : undef if ( lc( $aq->{Action} ) eq 'cancel') ;
                $aq->{ErrorCode} = $self->checkPermission($alias,$aq->{ENV},'ApplyAction');
            }
            
            if ( $aq->{ErrorCode} eq 0 and $pattern =~ /$aq->{ENV}/i)    
            {
                if (lc($aq->{Action}) eq 'getreqlist')
                {
                    $self->reqList($aq);
                } elsif (lc($aq->{Action}) eq 'cancel')
                {
                    $BU->_log ("Handle with action:- cancel");
                	for ( split /\:/, $aq->{Ins} )
                    {
                        $BU->_log ("starting cancel instance : ".$_);
                        $self->cancel($_);
                    }
                    $BU->_log ("sending feedback email to user");
                    my $body = $self->xget('/EDWEBS/Messages/msg[@code="EDWEBS-00004"]');
                    my $message = MIME::Lite->new(
                        From    => 'edwbld@expedia.com',
                        To      => $aq->{From}.";".$aq->{To},
                        Cc		=> $aq->{Cc},
                        Subject => 'EDWBuild - Retrieve info from edwdeploy',
                        Type    => 'multipart/mixed',
                    );
                    $body =~ s/<--From-->/$aq->{From}/gi;
                    $body =~ s/<--ReqList-->/$aq->{Ins}/gi;
                    $message->attach(Type    => 'text/html',
                                     Data	 => $body,
                                    );
                    $message->send('smtp',$self->xget('/EDWEBS/SMTP/Server/text()'),debug=>1);			
                    
                } else
                {
                    $aq->{ErrorCode} = 'EDWEBS-00403';
                    $BU->_log ("Bad parameter, Not supported action : ".$aq->{Action}." Failed on ".$aq->{ENV});
                    $self->actionResponser($aq); # goes into actionResponser process to send out error message.
                }
            } else
            {
               $BU->_log ("Apply action : ".$aq->{Action}." Failed on ".$aq->{ENV});
               $self->actionResponser($aq); # goes into actionResponser process to send out error message.
            }
            $BU->_log ("Move handled task to BuildReq folder");
            $imap->set_flag("seen",$msg);
            $imap->move('BuildReq',$msg);
            $imap->expunge;
            last;
        } else { next; }
    } 

    $imap->logout();
}

sub cancel
{
	my $self  = shift;
	my $msg   = shift;	
	my $msgRef = $self->getMsg($msg);
	if ( defined ($msgRef) )
	{
		$self -> longRunningBundleTerminate($msg,'m');
	} else
	{
		my $BU = BundleUtils->new($self->{'LogFile'});
		my $imap = $self->IMAPConnection;
		$imap->select($self->xget('/EDWEBS/IMAP/Folder/node()')) or die($BU->_log("Can not open folder with $@"));
		$imap->set_flag("seen",$msg);
		$imap->move($self->xget('/EDWEBS/IMAP/MoveTo/node()'),$msg);
		$imap->expunge;
		$imap->logout;
	}
}

sub IMAPConnection
{
	my $self = shift;
	my $imap;
	my $BU = BundleUtils->new($self->{'LogFile'});
	$imap = Mail::IMAPClient->new(
    Server   => $self->xget('/EDWEBS/IMAP/Server/node()'),
	Port     => 993,
	Ssl		 => 1,
    User     => $self->xget('/EDWEBS/IMAP/UserName/node()'),
    Password => $ENV{MailPWD}, # $self->xget('/EDWEBS/IMAP/Password/node()'),
	Timeout  => 60,
    #Debug    => 1
	) or die($BU->_log("Can not connect to ".$self->xget('/EDWEBS/IMAP/Server/node()')." with $?"));
	return $imap;
}

sub reqParser
{ 
  my $self = shift;
  my $imap;
  my $hmsg;
  my $mq;
  my $sbj;
  my ($alias,@raids);
  my $BU = BundleUtils->new($self->{'LogFile'});
  my $partten = lc($ENV{computername}) eq lc($self->xget('/EDWEBS/Cluster/Slave/@Server')) ? $self->xget('/EDWEBS/Cluster/Slave/@Partten') : $self->xget('/EDWEBS/Cluster/Master/@Partten');
  my $server = lc($ENV{computername}) eq lc($self->xget('/EDWEBS/Cluster/Slave/@Server')) ? $ENV{computername} : $self->xget('/EDWEBS/Cluster/Master/@Server');
  $server = uc($ENV{computername}) eq 'CHE-RDCEDW02' ? 'CHE-RDCEDW02' : $server;
  # connect to IMAP server 
  for (;;)
  {
	$imap = $self->IMAPConnection;
	if (not defined($imap))
	{
		sleep 300;
		$BU->_log("Issue when trying to connect to exchange server, sleeping for 300 sec. and retry");
		next;
	} else
	{
		last;
	}
  }
  $imap->select($self->xget('/EDWEBS/IMAP/Folder/node()')) or die($BU->_log("Can not open folder with $@"));
  my @msg = $imap->unseen; # Only looking for unseen emails to pick up requests
  
  # parse requests here return as a hash ref
  foreach my $msg(@msg)
  {
	$hmsg = $imap->parse_headers($msg,"date","From","To","Cc","Subject","Message-ID");
	$alias = $1 if $hmsg->{From}->[0] =~ /<(.*?)\@/ig;
	$hmsg->{Subject}->[0] =~ s/\s//gi;
	if ($hmsg->{Subject}->[0] =~ /^(\s*\[|FW:\s*\[)BLD_REQ\]:(.*?)Raid=/gi)
	{
		if ($hmsg->{Subject}->[0] =~ /$partten/i)
		{	
			$sbj = $self->subjectParser($hmsg->{Subject}->[0]);		
			$mq->{$msg} = {
							Subject      => $sbj,
							From         => $hmsg->{From}->[0],
							To           => $hmsg->{To}->[0],
							Cc           => $hmsg->{Cc}->[0],
							MessageID    => $hmsg->{"Message-ID"}->[0],
							ReceivedDate => $hmsg->{date}->[0]=~/,\s*(.*?)\s*[-|+]/?$1:$hmsg->{date}->[0]
						  };
			#$mq->{$msg}->{Body} = $imap->body_string($msg);
			@raids = split ":",$sbj->{raids};
			$mq->{$msg}->{BundleName} = $raids[0].'_'.$alias.'_'.$sbj->{ENV}.'_'.$BU->fdt('yyyymmddhh24miss');
			#$mq->{$msg}->{BundleName} = $msg;
			$mq->{$msg}->{ErrorCode} = $self->checkPermission($mq->{$msg}->{From},$sbj->{ENV},'Deploy');
            if ($mq->{$msg}->{From} =~ /expedia\.com/gi and ($mq->{$msg}->{MessageID} =~/\.SEA\.CORP\.EXPECN\.com/gi or $mq->{$msg}->{MessageID} =~/\@expedia\.com/gi))
            {
                $BU->_log("Valid requests.");
            } else
            {
                $BU->_log("Could be spoof requests.");
                $mq->{$msg}->{ErrorCode} = 'EDWEBS-00107';
            };					
			$mq->{MQCount}++;
			$imap->set_flag("seen",$msg);
			$imap->move($self->xget('/EDWEBS/IMAP/MoveTo/node()'),$msg);
			$imap->expunge;
			#last if $mq->{MQCount} == $self->xget('/EDWEBS/Bundle/MaxItem/node()'); # oooooonly get x requests each time.
			last; # get one request each time
		} else 
		{
			next;
		}
	} 
	elsif ($hmsg->{Subject}->[0] =~ /^(\[|FW:\[)BLD_REQ\]:(.*?)action=/gi) 
    {
        if ($hmsg->{Subject}->[0] =~ /$partten/gi)
        {
            $BU->_log("Assign task by move task to todo folder:".$server);
            $imap->move($server,$msg);
        } elsif ($hmsg->{Subject}->[0] =~ /prod/gi)
        {
            $BU->_log("Assign task by move task to todo folder: CHE-RDCEDW02");
            $imap->move('CHE-RDCEDW02',$msg);
        }
		$imap->expunge;
    } 
	else 
	{
		$BU->_log("moves non-request emails to Deleted Items for deploy account");
		$imap->move('Deleted Items',$msg);
		$imap->expunge;
	}
  }
  $imap->logout();
  $BU->_log(Dumper $mq);
  return $mq;
}

sub subjectParser
{
	my $self = shift;
	my $subject = shift;
	my @TmpArr;
	my @Raids;
	my $SubjRef;
	my $rlist;
	$subject =~ s/\s//gi; #remove blank
	$subject = $1 if ($subject =~ /\[BLD_REQ\]:([\S]+)/i);
	@TmpArr=split /\|/,$subject;
	my $BU = BundleUtils->new($self->{LogFile});
	for (@TmpArr)
	{
		$SubjRef->{ENV}=$1 if ($_=~ /ENV\s*=\s*(.*+)/i);
		$SubjRef->{BundleName}=$1 if ($_=~ /BundleName\s*=\s*([\S]+)/i);
		$SubjRef->{Stage}=$1 if ($_=~ /Stage\s*=\s*([\S]+)/i);
		$SubjRef->{Integrate}=$1 if ($_=~ /Integrate\s*=\s*([\S]+)/i);
		$SubjRef->{InfaUser}=$1 if ($_=~ /InfaUser\s*=\s*([\S]+)/i);
		$SubjRef->{InfaPass}=$1 if ($_=~ /InfaPass\s*=\s*([\S]+)/i);
		$SubjRef->{StartAt}=$1 if ($_=~ /StartAt=(\d+)/i);
		$SubjRef->{_DevMode_}=$1 if ($_=~ /_DevMode_=(\w+)/i);		

		# here are raid number validation.		
		if ($_=~ /raid\s*=\s*([\S]+)/i)
		{
			$SubjRef->{raids}=$1;
			for ( split ':',$SubjRef->{raids} )
			{
				$rlist .= $self->expand($_).":";				
			}
			$SubjRef->{RaidCount} = () = $rlist =~ /:/g;
			$rlist =~ s/:$//gi;
			$SubjRef->{raids} = $rlist;
			$SubjRef->{ErrorCode} = 'EDWEBS-00105' if $SubjRef->{RaidCount} > 20;
			@Raids = $BU->uniq($self->raidValidation($SubjRef->{raids}));
			if ( grep (/NotExists/i,@Raids) and $#Raids == 0 )
			{
				$SubjRef->{ErrorCode} = 'EDWEBS-00100';
			}
			elsif (grep (/NotExists/i,@Raids) and $#Raids > 0)
			{
				$SubjRef->{ErrorCode} = 'EDWEBS-00101';
			}
			elsif (grep (/edw/i,@Raids) and grep (/dmo/i,@Raids))
			{
				$SubjRef->{ErrorCode} = 'EDWEBS-00102';
			}
			else 
			{
				$SubjRef->{ErrorCode} = 0;
				$SubjRef->{RaidsType} = $Raids[0];
			}
		}
	}
	# varify bundle name
	if (length($SubjRef->{Stage}) > 0)
	{
		if ( $SubjRef->{RaidCount} > 1 and length($SubjRef->{BundleName}) == 0 )
		{
			$SubjRef->{ErrorCode} = 'EDWEBS-00103';
		}
		if( $SubjRef->{RaidCount} == 1 )
		{
			$SubjRef->{BundleName} = length($SubjRef->{BundleName}) == 0 ? $SubjRef->{raids} : $SubjRef->{BundleName};
		}
		if ( uc($SubjRef->{ENV}) ne "MLN" )
		{
			$SubjRef->{ErrorCode} = 'EDWEBS-00104';
		}
	}	
	#varify to see if InfaUser/InfaPass given on DEV.
	for (split ':',$SubjRef->{raids})
	{
		my $cl = `cl -c $_`;
		
		if ($SubjRef->{ENV} =~ /dev/i and $cl =~ /call\sInfaDeploy.cmd/gi)
		{
			$SubjRef->{ErrorCode} = 'EDWEBS-00501' if ( length($SubjRef->{InfaUser}) == 0 or length($SubjRef->{InfaPass}) == 0 );
		}				
	}
	
	$SubjRef->{ErrorCode} = 'EDWEBS-00502' if (length($SubjRef->{Integrate}) == 0 and uc($SubjRef->{ENV}) eq "RC");
	
	return $SubjRef;
}


sub validation
{
	my $self = shift;
	my $mq = shift;
	my $ErrorCode;
	my $Body;
	my @keys = grep !/MQCount/i, keys %$mq;
	my $BundleUtils = BundleUtils->new($self->{'LogFile'});
	foreach my $key (@keys)
	{
		if ( $mq->{$key}->{ErrorCode} || $mq->{$key}->{Subject}->{ErrorCode} )
		{
			$ErrorCode = $mq->{$key}->{ErrorCode} || $mq->{$key}->{Subject}->{ErrorCode};
			$BundleUtils->_log("Build request MsgID=[$key] not passed validation with ErrorCode=$ErrorCode");
			$self->sendMail($key,$mq->{$key});
			delete $mq->{$key}; 
			$mq->{MQCount}--;
			delete $mq->{MQCount} if $mq->{MQCount} == 0;
		}
	}
	return $mq;
}

sub expand
{
	my $self = shift;
	my $str = shift;
	my ($firstraid,$lastraid);
	my $expanded;
	return $str if $str !~ /~/g;
	if ($str =~ /(\d+)~(\d+)/i)
	{
		$firstraid = $1;
		$lastraid = $2;
	}
	for ($firstraid..$lastraid)
	{

		$expanded .= $_ == $firstraid ? "$_" : ":$_";
	}
	return $expanded;
}

sub getMsg
{
	my $self  = shift;
	my $Msgid = shift;
	my $MsgRef;	
	my @array;
	my $f = tie @array, "Tie::File", $self->{'CntlFile'};
	$f->flock;
	for(@array)
	{
		if ($_ =~ /$Msgid/i)
		{
			$MsgRef->{'Raids'} = $1 if ($_=~ /Raids=(.*+)/i);
			$MsgRef->{'From'} = $1 if ($_=~ /From=(.*+)/i);
			$MsgRef->{'To'} = $1 if ($_=~ /To=(.*+)/i);
			$MsgRef->{'Cc'} = $1 if ($_=~ /Cc=(.*+)/i);
			$MsgRef->{'PID'} = $1 if ($_=~ /PID=(.*+)/i);
			$MsgRef->{'BundleName'} = $1 if ($_=~ /BundleName=(.*+)/i);
			$MsgRef->{'ENV'} = $1 if ($_=~ /ENV=(.*+)/i);
			$MsgRef->{'ReceivedDate'} = $1 if ($_=~ /ReceivedDate=(.*+)/i);
			$MsgRef->{'BldStartDT'} = $1 if ($_=~ /BldStartDT=(.*+)/i);
			$MsgRef->{'CreateBundle'} = $1 if ($_=~ /CreateBundle=(.*+)/i);
			$MsgRef->{'Status'} = $1 if ($_=~ /Status=(.*+)/i);
			$MsgRef->{'Stage'} = $1 if ($_=~ /Stage=(.*+)/i);
			$MsgRef->{'Integrate'} = $1 if ($_=~ /Integrate=(.*+)/i);
			$MsgRef->{'ProcessID'} = $1 if ($_=~ /ProcessID=(.*+)/i);
		}
	}
	untie @array;
	return $MsgRef;
}

sub getMsgIDbyUser
{
	my $self  = shift;
	my $From = shift;
	my @Msgs;	
	my @array;
	my $f = tie @array, "Tie::File", $self->{'CntlFile'};
	$f->flock;
	for(@array)
	{
		push @Msgs, $1 if $_ =~ /(\d+)\|from=(.*?)$From\@/i;
	}
	untie @array;
	return @Msgs;
}

sub getMsgIDbyEnv
{
	my $self  = shift;
	my $Env = shift;
	my @Msgs;	
	my @array;
	my $f = tie @array, "Tie::File", $self->{'CntlFile'};
	$f->flock;
	for(@array)
	{
		push @Msgs, $1 if $_ =~ /(\d+)\|ENV=$Env/i;
	}
	untie @array;
	return @Msgs;
}

sub sendMsg
{
	my $self    = shift;
	my $MQMsgid = shift;
	my $MQKey   = shift;
	my $MQValue = shift;
	my @array;
	my $f = tie @array, "Tie::File", $self->{'CntlFile'};
	$f->flock;
	for(@array)
	{
		if ($_ =~ /$MQMsgid/i)
		{
			s/$MQKey=(.*+)/$MQKey=$MQValue/i;
		}
	}	
	untie @array;
	return $?
}


sub msgTable
{
	my $self    = shift;
	my $MQMsgid = shift;
	my @array;
	my $f = tie @array, "Tie::File", $self->{'CntlFile'};
	$f->flock;
	#push @array,"*"x60;
	for my $i ('Raids','From','To','Cc','ENV','ReceivedDate','PID','BundleName','BldStartDT','CreateBundle','Status','Stage','Integrate','ProcessID')
	{
		push @array,$MQMsgid."|$i=";
	}
	untie @array;
	return $?
}


sub msgCleanUp
{
	my $self    = shift;
	my $MQMsgid = shift;
	my @array;
	my $f = tie @array, "Tie::File", $self->{'CntlFile'};
	$f->flock;
	@array = grep (! /^$MQMsgid\|/gi ,@array);
	untie @array;
	return $?
}

sub raidValidation
{
	my $self = shift;
	my $raid = shift;
	my ($output,$edw,$ldw,$cmd,$rt,$i);
	my @raids = split ':', $raid;
	my @depots;
	
	foreach my $r (@raids)
	{
		$edw = "//depot/edw/Common/DBBuild/DEV/db/HotFix/Bundles/RaidFiles/raid$r.txt";
		$ldw = "//depot/dmo/Common/DBBuild/DEV/db/HotFix/Bundles/RaidFiles/raid$r.txt";
		for ($ldw,$edw)
		{
			$i++;
			$cmd = "p4 files $_";
			#print "$i=$cmd\n";
			open ( FILE, "$cmd 2>&1 |" ) or die "Couldn't run command:  $cmd\n";
			{
			  local( $/ );
			  $output = <FILE>;
			}
			close ( FILE );
		    next if $output =~ /delete change/i;
			if ($output =~ /\.txt\#\d/i)
			{
				$rt = $1 if $_=~/depot\/(.*?)\//gi;
				last;
			}
			if ($i == 2)
			{
				$rt = 'NotExists';
			}
			undef $output;
		}
		$i = 0;
		push @depots,$rt;
	}
return @depots;
}


sub longRunningBundleTerminate
{
	my $self = shift;
	my $msgID = shift;
	my $sw = shift;
	my $BundleUtils = BundleUtils->new($self->{'LogFile'});
	my $BldStartDT = $self->getMsg($msgID)->{BldStartDT};
	my ($cmd,$output);
	if ( $sw eq "m" or Date_Cmp($BundleUtils->fdt(),DateCalc($BldStartDT,'+'.$self->xget('/EDWEBS/Bundle/LongRunningWaitTime/node()').' minutes')) > 0 )
	{
		$cmd = "wmic process where (ParentProcessId=".$self->getMsg($msgID)->{PID}.") get Caption,ProcessId,CommandLine";
		$output = q{<tr><td width="12%" bgcolor="#C0C0C0"><b><font face="Verdana" size="2">LastRunningTasks</font></b></td><td width="87%">
		<table border="1" width="100%" bordercolorlight="#000000" style="border-collapse: collapse; border: 1px dashed #000000" cellspacing="1" bgcolor="#FFFFCC">
					<tr><td><pre><b>};
		$output .= `$cmd`;
		my $exitcode = $self->taskkill($self->getMsg($msgID)->{PID});
		if ($exitcode == 0)
		{
			$self->sendMsg($msgID,'Status','Aborted');
			$output .= "\n Process Aborted successfully. \n"
		} else {
			$output .= "\n $exitcode \n";
		}
		$output .= q{</b></pre></td></tr></table></td></tr>};
	}
	return "$output\n";
}

sub bLogger
{
	my $self = shift;
	my $msg	 = shift;
	my $BundleFolder = shift;
	my $BuildBy     = $ENV{USERNAME};
	my $whatEnvis	= $self->getMsg($msg)->{ENV};
	my $BStartDT    = $self->getMsg($msg)->{BldStartDT};
	my $OpenedBy	= $self->getMsg($msg)->{From};
	my $Raids		= $self->getMsg($msg)->{Raids};
	my $ReceivedDate= $self->getMsg($msg)->{ReceivedDate};
	my $status 	    = $self->getMsg($msg)->{Status};
	my $processID;
	my $BundleUtils = BundleUtils->new($self->{'LogFile'});
	my ($sql,$sth,$rc);
	my $DBC = DBComm->new($self->{'LogFile'});	
	my $DBH = $DBC->conn('sql','chexsqledw04','EDWDE','','');
	#my @BldLogs = $self->logsFetcher($BundleFolder);
	
	$sql = qq{select isnull(max(processid)+1,1) as processid 
				from dbo.Bundle_Build_Process_Hist};				
	$sth = $DBC->execSQL($DBH, $sql);
	$processID = $sth->fetchrow_array;
	$OpenedBy = substr($OpenedBy,0,index($OpenedBy,'<'));
	$sql = qq{insert into dbo.Bundle_Build_Process_Hist(ProcessID
															 ,Raid
															 ,BuildBy
															 ,Env
															 ,Status
															 ,BStartDT
															 ,BEndDT
															 ,OpenedBy
															 ,OpenDate
															 ,msgid
                                                             ,BundleName
                                                             ,RunOn) 
													  values($processID
															 ,'$Raids'
															 ,'$BuildBy'
															 ,'$whatEnvis'
															 ,'$status'
															 ,'$BStartDT'
															 ,getdate()
															 ,'$OpenedBy'
															 ,'$ReceivedDate'
															 ,'$msg'
                                                             ,'$BundleFolder'
                                                             ,'$ENV{computername}')};
															 
	#$BundleUtils->_log($sql);
	$sth = $DBC->execSQL($DBH, $sql);
	$sth->finish;
	# my ($s,$e,$a);
	# $s=0;
	# $e=99;
	# $a = scalar(@BldLogs)%100 == 0 ? int(scalar(@BldLogs)/100) : int(scalar(@BldLogs)/100)+1; 
	# $a = 2 if ($a == 1); # make sure goes into loop when length of file less than 100..,
	# for (1..((scalar(@BldLogs) < 100) ? $a-1 : $a))
	# {
		# $sql = qq{update edwtbldr.Bundle_Build_Process_Hist
					 # set logs = nvl(logs,' ') \|\| '@BldLogs[$s..$e]'
				   # where processid = $processID};
		# $BundleUtils->_log($_);
		# $sth = $DBC->execSQL($DBH, $sql);
		# $sth->finish;
		# $s=$e+1;
		# $e= (($e+100) > scalar(@BldLogs)) ? ($e=scalar(@BldLogs)) : ($e=$e+100);		
	# }

	$DBC->disconn($DBH,$sth);
	
	#print "\n>>>Logs for Bundle $msg are all archived, you can query table edwtbldr.Bundle_Build_Process_Hist by processID: $processID for details\n";
	$self->sendMsg($msg,'processID',$processID);
}

sub bundlebuildAutoUpd
{
	my $self = shift;
    my $branch = shift;
    my $BobHome = lc($ENV{computername}) eq lc($self->xget('/EDWEBS/Cluster/Slave/@BobHome')) ? $ENV{computername} : $self->xget('/EDWEBS/Cluster/Master/@BobHome');
    my $BundleUtils = BundleUtils->new($self->{'LogFile'});
    my $fixedname= (lc($branch) eq 'dw' ? 'BundleBuild.pl' : 'BundleBuild_Dev.pl');
	my $p4ver = `p4 files //depot/tools/$branch/BundleBuild.pl`;
	my $localvercmd = "perl -S $BobHome\\bin\\$fixedname -v";
    my $localver = `perl -S $BobHome\\bin\\$fixedname -v`;
	my $op;
	$p4ver = $1 if $p4ver =~ /BundleBuild.pl#(\d+)/i;
	$localver = $1 if $localver =~ /(\d+)/i;    
	if ( $p4ver != $localver )
	{
		$BundleUtils->_log("P4 has version $p4ver but local version is $localver");
		# print screen out to current directory with name BundleBuild.pl " bob\bin "
		$op = `p4 print -o $BobHome\\bin\\$fixedname //depot/tools/$branch/BundleBuild.pl#$p4ver`;
		if ( $op =~ /no file\(s\) at that revision/gi)
		{
			$BundleUtils->_log("No such version of file exists on p4, version=$p4ver");
		} else
		{
			$BundleUtils->_log("BundleBuild.pl synced! Current version is $p4ver.");
		}
	}
	# we need to check version for //depot/tools/dw/dw/* not only this one. 
	# We should have enough time to do in future so since those files not changed often.
}

sub logsFetcher{
	my $self = shift;
	my $msg = shift;
	my $switch = shift; # 1 = Joined content of files, 
	my @Logs;
	my $BU = BundleUtils->new($self->{LogFile});	
	my $LogFileDir = $self->xget('/EDWEBS/Bundle/RootDir/@dir')."\\$msg\\BusinessSystems";
	my $LogFile;
	my @LogFiles = File::Find::Rule->new->name("*.log","*.txt")->in($LogFileDir);
	my @InfaHistLoadLogs = File::Find::Rule->new->name("InfaHistLoad.log")->in($LogFileDir);
	my @lf;
	@LogFiles = grep (/ApplyBundledHotfixes_LOG|BusinessSystems\/PRODEDW/,@LogFiles);
	push @LogFiles,@InfaHistLoadLogs;
	@LogFiles = sort { -M $b <=> -M $a } @LogFiles; # sort files by date desc
	foreach my $l(@LogFiles)
	{
		push @lf,$l if (-f $l);
	}
	foreach $LogFile(@lf)
	{
		$BU->_log("Fetching log $LogFile...");	
		open(DAT, $LogFile) or die ("can not open log $LogFile with $!");
		push @Logs, "#-----------------------------------------------------------------------\n";
		push @Logs, "#Bundle Log $LogFile is as follows:\n";
		push @Logs, "#-----------------------------------------------------------------------\n\n";
		if ((-s $LogFile)/(1024*1024) > 3)
		{
			push @Logs, "#Bundle Log $LogFile is ignored due to size large than 3m:\n";
			close(DAT);
			next;
		}
		while (<DAT>)
		{
			$_ = substr($_,0,200) if length($_) > 200;
			$_ =~ s/\'/\'\'/g;			
			push @Logs,$_;			
		}
		push @Logs,"\n\n";
		close(DAT);
	}
	if ($switch == 1)
	{
		return @lf 
	} else { return @Logs; }
}

sub scpProcDir{
	my $self = shift;
	my $msg = shift;
	my $Env  = shift;
	my $host;
	my $user;
	my $output;
	my $FileName;
	my $cmd;
	my $BU = BundleUtils->new($self->{LogFile});
	##########Pre-defined Informatica ProFile
	my $PMROOTDIR         = "/informatica/pc851/server/infa_shared";
	my $PMSOURCEFILEDIR   = "$PMROOTDIR/SrcFiles/infa01";
	my $PMTARGETFILEDIR   = "$PMROOTDIR/Working/infa01/TgtFiles";
	my $PMSESSIONLOGDIR   = "$PMROOTDIR/SessLogs/infa01";
	my $PMSOURCEDIR       = "/ExternalDataFeed";
	my $PMEXTERNALPROCDIR = "$PMROOTDIR/Working/infa01/ExtProc";
	my $PMCMDDIR          = "/informatica/pc851/server/bin";
	###########################################

	switch($Env) 
	{
		case /dev/i { $host="cheletledw001";$user="infadm" }
		case /test/i { $host="cheletledw011";$user="infadm" }
		case /ppe/i { $host="cheletledw011";$user="v-azhu" }
		case /rc/i { $host="cheletledw021";$user="infadm" }
		case /mln/i { $host="cheletledw201";$user="infadm" }
		else { $host="cheletledw011";$user="v-azhu" }
	}

	my @TmpFiles = File::Find::Rule->file()->name("*.*",".*")->in($self->xget('/EDWEBS/Bundle/RootDir/@dir')."\\$msg\\BusinessSystems\\Informatica\\ExternalProc\\PMEXTERNALPROCDIR");
	for (@TmpFiles)
		{
			$cmd = $self->xget('/EDWEBS/Bundle/CygHome/@dir')."\\bin\\cygpath -u $_";
			$FileName = `$cmd`;
			chomp $FileName;
			$output = system ($self->xget('/EDWEBS/Bundle/CygHome/@dir')."\\bin\\scp $FileName $user\@$host:/informatica/pc851/server/infa_shared/Working/infa01/ExtProc");
			$BU->_log( "Source: $FileName" );
			$BU->_log( "Destination: $host:/informatica/pc851/server/infa_shared/Working/infa01/ExtProc" );
			$FileName = basename($FileName);
			# looks like works fine without fork...
			#print "ssh $user\@$host 'ls -l /informatica/pc851/server/infa_shared/Working/infa01/ExtProc/$FileName'\n";		
			$output = system($self->xget('/EDWEBS/Bundle/CygHome/@dir')."\\bin\\ssh $user\@$host 'dos2unix /informatica/pc851/server/infa_shared/Working/infa01/ExtProc/$FileName'");
			$BU->_log ("dos2unix ...".$output);
			sleep 3;
			$output = system($self->xget('/EDWEBS/Bundle/CygHome/@dir')."\\bin\\ssh $user\@$host 'chmod 775 /informatica/pc851/server/infa_shared/Working/infa01/ExtProc/$FileName'");
			$BU->_log ("chmod ...".$output);
			sleep 3;
			$output = system($self->xget('/EDWEBS/Bundle/CygHome/@dir')."\\bin\\ssh $user\@$host 'ls -l /informatica/pc851/server/infa_shared/Working/infa01/ExtProc/$FileName'");
			$BU->_log ("verify the file uploaded ...".$output);
			exit ($?) if $? > 0;
		}
}

sub infaPrepUpd
{
	my $self     = shift;
	my $msg      = shift;
	my $InfaUser = shift;
	my $InfaPass = shift;

	#return 1 if not defined $InfaUser;
	#my $RootDir = $self->xget('/EDWEBS/Bundle/RootDir/@dir');
	my $RootDir = "D:\\Raids";
	system("attrib -R $RootDir\\$msg\\BusinessSystems\\Common\\DBBuild\\db\\release\\InfaPrep.cmd");

	open (InfaRep,">$RootDir\\$msg\\BusinessSystems\\Common\\DBBuild\\db\\release\\InfaPrep.cmd") or die $@;

	print InfaRep <<InfaRepEOF;
\@echo off

set ERRORLEVELTEMP=0

:Work

\@echo *********************************************************
\@echo ********** Connect to Informatica ***********************
\@echo *********************************************************
\@echo.
\@set Infa_User=$InfaUser
\@set Infa_Pass=$InfaPass
pmrep connect -r %Infa_Repository% -h %Infa_Host% -o %Infa_Port% -n %Infa_User% -X Infa_Pass
if ERRORLEVEL 1 goto Problem

\@echo.
\@echo Preparing for Informatica deployment -- Complete

goto Exit

:Problem
\@echo.
\@echo Preparing for Informatica deployment -- FAILED!!!
set ERRORLEVELTEMP=1

:Exit
cscript SetErrorlevel.vbs %ERRORLEVELTEMP%
InfaRepEOF
	close(InfaRep);

	return $?;
}


sub rmBundleFiles
{
	my $self = shift;
	my $BundleRootDir = $self -> xget('/EDWEBS/Bundle/RootDir/@dir');
	my $rule = File::Find::Rule->new;
	$rule->maxdepth(1);
	my @thefiles = $rule->directory->in( "$BundleRootDir" );

	foreach my $file(@thefiles)
	{
		system( "rd /S /Q ".`cygpath -w $file` ) if ((-d $file) and $file =~ /\d$/ and (-C $file) > $self->xget('/EDWEBS/Bundle/MaxkeepDays/node()'));
	}
}

sub bobLogArchive
{
	my $self = shift;
	my $src = $self -> xget('/EDWEBS/BobLog/Archive/Src/node()');
	my $tgt = $self -> xget('/EDWEBS/BobLog/Archive/Tgt/node()');
	my $maxarchiveDays = $self -> xget('/EDWEBS/BobLog/Archive/MaxArchiveDays/node()');
	my $rule = File::Find::Rule->new;
	$rule->maxdepth(1);
	my @thefiles = $rule -> name('*.txt') ->in($src);

	foreach my $file(@thefiles)
	{
		system ("robocopy $src $tgt ".basename($file)." /MOV" ) if ( (-C $file) > $maxarchiveDays );		
	}
}

sub stageBundle
{
	my $self = shift;
	#my $MsgId = shift;
	my $MQ = shift;
	my $DeployStatus = shift;
	my $cmd;
	my $BU = BundleUtils->new($self->{'LogFile'});
	my $Output;
	# Doing stage stuffs
	if ( $DeployStatus ne "Succeed" and $MQ->{Subject}->{Stage} =~ /No/i )
	{
		$BU->_log("An error occured during Deployment, It's not good to stage bundle");
	} else
	{
		$cmd = "stgins.cmd ".$MQ->{Subject}->{raids};
		$cmd .= " ".$MQ->{Subject}->{BundleName};
		$cmd .= " ".$MQ->{Subject}->{RaidsType};
		$cmd .= " ".$MQ->{Subject}->{Stage};
		$cmd .= " ".$MQ->{BundleName};
		$cmd .= " > ".$self->xget('/EDWEBS/Bundle/RootDir/@dir')."\\StageLogs\\StgLog_".$MQ->{Subject}->{BundleName};
		$cmd .= ".txt 2>&1";
		$BU->_log("Starting stage: $cmd");
		system($cmd);
		if ( $? == 0 )
		{
			$Output .= '<a href="file://'.$ENV{COMPUTERNAME}.'/raids/StageLogs/StgLog_'.$MQ->{Subject}->{BundleName}.'.txt">ClickHereViewStageLog</a></font></b><br>';
			$Output .= '<a href="file://'.$ENV{COMPUTERNAME}.'/raids/StageLogs/CBundle'.( $MQ->{Subject}->{Stage} =~/only/i ? $MQ->{Subject}->{BundleName} : $MQ->{BundleName} ).'.txt">ClickHereViewCreateBundleLog</a></font></b><br>';
			$Output .= "<pre>";
			$Output .= "<b>BundleName : ".$MQ->{Subject}->{BundleName}."</b><br>";
			$Output .= q{<table border="1" width="100%" bordercolorlight="#000000" style="border-collapse: collapse; border: 1px dashed #000000" cellspacing="1" bgcolor="#FFFFCC">
							<tr><td><pre>};
			$Output .= "";
			for(split ':', $MQ->{Subject}->{raids})
			{
				$BU->_log( "$_ " . $self->getJiraDetailByItemID($_)->[0] );
				$Output .= "$_  ".$self->getJiraDetailByItemID($_)->[0]." [ Developer : ".$self->getJiraDetailByItemID($_)->[1]." ]\n";
			}
			$Output .= q{</pre></td></tr></table>};
			$Output .= "<br>Bundle executable : ";
			$Output .= "\\\\chc-filidx\\DSTest\\EDW\\EDW_HF\\".$BU->fdt('yyyymmdd')."\\".$MQ->{Subject}->{BundleName}.".exe<br><br>";
			$Output .= q{<table border="1" width="100%" bordercolorlight="#000000" style="border-collapse: collapse; border: 1px dashed #000000" cellspacing="1" bgcolor="#FFFFCC">
							<tr><td><pre>};	
			$Output .= "<br>";							
			for(split ':', $MQ->{Subject}->{raids})
			{				
				$BU->_log( "$_ " . $self->getJiraDetailByItemID($_)->[0] );
				$Output .= `cl -m $_`;
			}
			$Output .= q{</pre></td></tr></table>};
			$Output .= "</pre>";
		} else
		{
			$BU->_log("An error occured during stage!");
			$Output .= "<b><font color=red>An error occured during stage, ExitCode = $?</b></font> please find logs for details.\n";
			$Output .= '<br><a href="file://'.$ENV{COMPUTERNAME}.'/raids/StageLogs/StgLog_'.$MQ->{Subject}->{BundleName}.'.txt">ClickHereViewStageLog</a></font></b><br>';
			$Output .= '<br><a href="file://'.$ENV{COMPUTERNAME}.'/raids/StageLogs/CBundle'.$MQ->{Subject}->{BundleName}.'.txt">ClickHereViewCreateBundleLog</a></font></b><br>';
		}
	}
	return $Output;
}
sub getJiraDetailByItemID
{
	my $self = shift;
	my $Item = shift;
	my $DBC = DBComm->new($self->{'LogFile'});
	my $DBH = $DBC->conn('SQL',$self->xget('/EDWEBS/JiraConnString/Server/node()'),$self->xget('/EDWEBS/JiraConnString/Database/node()'),'','');
	my $sql = "select title,developer from dbo.jiraitems where itemkey = 'EDW-".$Item."'";
	my $sth = $DBH->prepare($sql);
	$sth->execute();
	my $XRef = $sth->fetchrow_arrayref;
	$self->_log($sql."\n".$sth->errstr) if ($sth->err);
	$DBC->disconn($DBH,$sth);
	if ( defined($XRef) )
	{ 	
		return $XRef; 
	} else 
	{ 
		my $Res;
		my $URL = "https://jira/jira/si/jira.issueviews:issue-xml/EDW-$Item/EDW-$Item.xml";
		my $ua = LWP::UserAgent->new;
		$ua->timeout(300);
		my $req = HTTP::Request->new(GET => $URL);
		$req->authorization_basic($self->xget('/EDWEBS/JiraConnString/UserName/node()'),$self->xget('/EDWEBS/JiraConnString/Password/node()'));
		my $XMLRaw = $ua->request($req)->decoded_content;
		return ['NotFound','NotFound'] if $XMLRaw =~ /Could not find issue with issue key EDW-$Item/gi;
		my $XP = XML::XPath->new( xml => $XMLRaw );	
		$Res->[0] = $XP->find( '/rss/channel/item/title/node()' );
		$Res->[1] = $XP->find( '/rss/channel/item/customfields/customfield[@id="customfield_11814"]/customfieldvalues/node()' );
		return $Res;
	}
}

sub Integrate
{
	my $self = shift;
	my $raids = shift;
	my $IntegrateLog;
	my $BU = BundleUtils->new($self->{'LogFile'});
	my $DBC = DBComm->new($self->{'LogFile'});
	my $DBH = $DBC->conn('SQL',$self->xget('/EDWEBS/JiraConnString/Server/node()'),$self->xget('/EDWEBS/JiraConnString/Database/node()'),'','');
	$raids =~ s/:/ /g;
	$BU->_log ("Starting integrate jira [$raids]");
	$IntegrateLog = `integrate.pl $raids`;
	my $errorcode = $?;
	$IntegrateLog =~ s/\'/\'\'/g;
	#print "$IntegrateLog\n";
	my $sql = qq{insert into dbo.JiraItemIntegration (raids
											   ,IntegrateTime
											   ,IntegrateLogs
												) 
										values ('$raids'
												,getdate()
												,'$IntegrateLog'
										)
	};
	my $sth = $DBH->prepare($sql);
	my $rc = $sth->execute();
	$BU->_log ("$sql\n".$sth->errstr) if ($sth->err);
	$sth->finish;
	$DBC->disconn($DBH,$sth);
	$BU->_log("Item ".$raids." complete integration with log:\n".$IntegrateLog);
	return $errorcode?"EDWEBS-00920":0;
}

1;
