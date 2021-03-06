require 5.000;
$| = 1;
use strict;

our ( $Scriptdir, $Scriptfile );

BEGIN {
	use File::Basename;
	$Scriptdir  = dirname(__FILE__) . "\\";
	$Scriptfile = basename(__FILE__);

}

use lib $Scriptdir . "..\\";
use praqma::scriptlog;
use praqma::trigger_helper;
use praqma::pcc;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME = "ACC_DELIVER_BASELINE";

our %install_params = (
	"name"     => $TRIGGER_NAME,                                                               # The name og the trigger
	"mktrtype" => "-ucmobject -all -postop mkbl_complete,deliver_cancel,deliver_complete ",    # The stripped-down mktrtype command
	"supports" => "ccucm_plugin_supported",                                   # csv list of generic and/or custom VOB types (case insensetive)
	"comment"  => "Start deliver of remotely created development baselines"
);

# File version
our $VERSION = "1.0";
our $BUILD   = "5";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#
#    $Scriptfile  version $VERSION.$BUILD
#
#    This script is intended as ClearCase trigger script for the
#    $TRIGGER_NAME trigger.
#
#    Delivers a baseline created in child stream to the integration stream 
#    if the mastership of the child stream is different from the  
#    mastership of the integration stream
#
#    The trigger fires after the mkbl_complete event
#
#    This script supports self-install (execute with the -install
#    switch to learn more).
#
#    Read the POD documentation in the script for more details
#    Date:       2012-03-03
#    Author:     Jens Brejner, jbrejner\@praqma.net
#    Copyright:  Praqma A/S
#    License:    GNU General Pulic License v3.0
#    Support:    mailto:support\@praqma.net
#
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2012-05-30  Jens Brejner   Ignore latest baselines for returning 
                           mastership, they will be changed on next 
                           execution (v1.0.5)
2012-04-26  Jens Brejner   Add return of mastership (v1.0.4)
2012-04-24  Jens Brejner   Handle deliver in progress (v1.0.3)
2012-04-10  Jens Brejner   Optional change baseline mastership, default is
                           not. Suppress confirmation message (v1.0.2)
2012-04-03  Jens Brejner   Initial version (version 1.0.1)

----------  -------------  ----------------------------------------------

ENDREVISION

######################################## Basic trigger stuff ###############################################

my %triggerconfig;
our $log = scriptlog->new();
$log->conditional_enable();
$log->set_verbose();

our $logfile = $log->get_logfile;
$log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
$log->dump_ccvars();                            # Run this statement to have the trigger dump the CLEARCASE variables

our $clearcase = pcc->new();

#Enable the features in trigger_helper
our $thelp = trigger_helper->new();
$thelp->get_config( \%triggerconfig );
$thelp->enable_install( \%install_params );     #Pass a reference to the install-options
$thelp->require_trigger_context;

our $semaphore_status = $thelp->enable_semaphore_backdoor();
$log->information($semaphore_status);

exit 0 unless $clearcase->IsReplicated( vobtag => $ENV{CLEARCASE_VOB_PN} );
exit 0 if ( $ENV{CLEARCASE_POP_KIND} eq lc('deliver_start') || $ENV{CLEARCASE_POP_KIND} eq lc('rebase_start') );

########################### MAIN ###########################
my ( $bl_stream, @bl_list, $dev_master, $int_stream, $int_master );

if ( $ENV{CLEARCASE_OP_KIND} eq 'mkbl_complete' ) {
	remote_site_actions();
	exit 0;
}

if ( ( $ENV{CLEARCASE_OP_KIND} eq 'deliver_cancel' ) || ( $ENV{CLEARCASE_OP_KIND} eq 'deliver_complete' ) ) {
	master_site_actions();
	exit 0;
}

$log->assertion_failed( "$Scriptfile did not expect to end here at line " . __LINE__ );

################################### SUBS ###################################

sub master_site_actions {
	$log->information("Running master site actions");

	my $src_stream = "stream:$ENV{CLEARCASE_SRC_STREAM}";
	$log->information("Source stream name is [$src_stream]");
	my $src_master = $clearcase->get_master_replica( object => "$src_stream" );
	$log->information("Stream [$src_stream] is mastered at [$src_master]");

	$int_stream = "stream:$ENV{CLEARCASE_STREAM}";
	$log->information("Stream for $ENV{CLEARCASE_POP_KIND} opereration is [$int_stream]");
	$int_master = $clearcase->get_master_replica( object => "$int_stream" );
	$log->information("Stream [$int_stream] is mastered at [$int_master]");

	if ( $src_master eq $int_master ) {
		$log->information("Target and source streams has same mastership. We are done");
		exit 0;
	}

	my (%ignore_these,@members);
	# Get the direct baselines involved
	@bl_list = listbaselines();
	
	# 
	foreach (@bl_list) {
		$log->information( "Retrieving dependencies for baseline $_");
		$ignore_these{$_}++;
		# Only need the lines that looks like baseline names from the output, a baseline name contains the @ sign
		my @output = $clearcase->ct( command => 'lsbl -fmt %[member_of_closure]p ' . $_);
		$log->information( "Got output:\n" . join( "\t", @output ) );
		chomp @output;
		
		my @members = grep {/\S+@\\\S+/} @output ;
		$log->information( "Isolated strings output:\n" . join( "\t", @members ) );		
		foreach my $string (split (/\s+/, join (' ', @members) ) ){
			chomp($string);
			$log->information( "Ignoring $string");		
			$ignore_these{"baseline:$string"}++
		}
 
	} 
	$log->information( "Prepared to ignore these baselines:\n" . join( "\t", keys %ignore_these ) );
	
	# Search baselines on stream and get their baseline mastership too
	my @baseline_mastership = $clearcase->ct( command => 'lsbl -fmt %[master]p\t%Xn\n -stream ' . $src_stream );
	$log->information( "Found the following baselines on stream:\n" . join( "\t", @baseline_mastership ) );

	# Filter the baselines based on mastership and eventually change their mastership
	foreach my $victim ( grep { /^\Q$int_master/ } @baseline_mastership ) {
		my ( $master, $foreign_bl ) = split( /\s+/, $victim );
		next if exists $ignore_these{$foreign_bl};
		$log->information("Returning [$foreign_bl] mastership to [$src_master]");
		my $chmaster_cmd = "chmaster -c \"Trigger $TRIGGER_NAME returned mastership\" $src_master $foreign_bl";
		$clearcase->ct( command => $chmaster_cmd );
	}

}


sub remote_site_actions {
	$log->information("Running remote site actions");
	$bl_stream = "stream:$ENV{CLEARCASE_STREAM}";
	$log->information("Baseline stream name is [$bl_stream]");

	# Create list of baselines created
	@bl_list = listbaselines();

	# Get name of the projects integration stream
	$int_stream = get_integration();

	# The baseline(s) are on the integration stream so we are done
	if ( $int_stream eq $bl_stream ) {
		$log->information("Exit early & happy, the baseline is created on integration stream");
		exit 0;
	}

	# Where is the integration branch mastered ?
	$int_master = $clearcase->get_master_replica( object => "$int_stream" );
	$log->assertion_failed("Required value for Integration stream's master replica (\$int_master) is empty") unless ($int_master);
	$log->information("Integration stream's master replica (\$int_master) is $int_master");

	# Where is the development branch mastered ?
	$dev_master = $clearcase->get_master_replica( object => $bl_stream );
	$log->assertion_failed("Required value for Development stream's master replica (\$dev_master) is empty") unless ($dev_master);
	$log->information("Development stream's master replica (\$dev_master) is $dev_master");

	my $deliver_is_in_progress = $clearcase->IsInProgress( stream => $bl_stream, operation => "deliver" );

	if ($deliver_is_in_progress) {

		# Deliver in progress, cant deliver
		warn_cant_deliver();
		exit 0;
	}
	elsif ( $int_master eq $dev_master ) {

		# Master ship is same, don't do posted delivery
		$log->information("Exit early & happy, Mastership is same");
		exit 0;
	}
	else {

		# Got work to do.
		$log->information("Target stream mastership is not local, need to deliver baseline");
		deliver();
	}

	exit 0;
}

sub warn_cant_deliver {

	# Called if deliver already in progres, then we cant deliver automatically
	my $msg = setwarn_msg();
	if ( defined( $ENV{CLEARCASE_CMDLINE} ) || defined( $ENV{ATRIA_WEB_GUI} ) ) {

		$log->warning($msg);

	}
	else {

		$log->enable(1);
		$log->set_verbose();
		$log->warning($msg);
		my $ret = qx(clearprompt proceed -type warning -default proceed -prompt "$msg" -mask proceed);
	}
}

sub get_integration {
	my $reply = $clearcase->get_integration_stream( project => "project:$ENV{CLEARCASE_PROJECT}" );
	$log->assertion_failed("Required value for Integration stream (\$reply) is empty") unless ($reply);
	$log->information("Integration stream is [$reply]");
	return $reply;
}

sub listbaselines {

	# Create list of baselines created
	my @_bl_list = split( /\s+/, $ENV{CLEARCASE_BASELINES} );
	$log->assertion_failed("No baselines found") unless ( $#_bl_list > -1 );

	foreach (@_bl_list) {
		$_ = "baseline:$_";
	}
	return @_bl_list;
}

sub setwarn_msg {

	my $warnmessage = <<ENDMESSAGE;

This the Trigger $TRIGGER_NAME.

Delivery is already in progress for stream $ENV{CLEARCASE_STREAM},
so the baselines $ENV{CLEARCASE_BASELINES} 
can NOT be automatically delivered.

Please wait for syncronization and deliver the baseline(s) manually.

ENDMESSAGE

	return $warnmessage;

}

sub deliver {

	my @to_be_delivered;
	foreach my $baseline (@bl_list) {

		# Check baseline(s) mastership
		my $bl_master = $clearcase->get_master_replica( object => $baseline );
		$log->information("$baseline is mastered at $bl_master");
		if ( $bl_master eq $dev_master ) {
			push @to_be_delivered, $baseline;

			if ( $triggerconfig{ChgBaselineMasterShip} ) {

				# Only change mastership unless disabled through configuration file
				$log->information("Changing mastership of baseline $baseline to $int_master");
				my $chmaster_cmd = "chmaster -c \"Trigger $TRIGGER_NAME changed mastership for Promotion Level update\" $int_master $baseline";
				$clearcase->ct( command => $chmaster_cmd );
			}
		}
		else {
			$log->information("Baseline mastership of $baseline is $bl_master");
		}
	}

	# Start deliver of baseline to default target.
	push @to_be_delivered, @bl_list unless ( $#to_be_delivered > -1 );
	my $forcedeliver = !( $triggerconfig{ShowConfirmation} ) ? "-force" : "";
	my $deliver_cmd = "deliver $forcedeliver -stream $bl_stream -baseline " . join( ',', @to_be_delivered );
	$clearcase->ct( command => $deliver_cmd );
	$log->information( "Deliver status is now:\n" . $clearcase->IsInProgress( stream => $bl_stream, operation => "deliver" ) );

}

__END__
