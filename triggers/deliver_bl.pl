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
	"name"     => $TRIGGER_NAME,                                              # The name og the trigger
	"mktrtype" => "-ucmobject -all -postop mkbl_complete ",                   # The stripped-down mktrtype command
	"supports" => "ccucm_plugin_supported",                                   # csv list of generic and/or custom VOB types (case insensetive)
	"comment"  => "Start deliver of remotely created development baselines"
);

# File version
our $VERSION = "1.0";
our $BUILD   = "2";

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

exit 0 unless $clearcase->IsReplicated( $ENV{CLEARCASE_VOB_PN} );
exit 0 if ( $ENV{CLEARCASE_POP_KIND} eq lc('deliver_start') || $ENV{CLEARCASE_POP_KIND} eq lc('rebase_start') );

########################### MAIN ###########################
if ( $ENV{CLEARCASE_OP_KIND} eq 'mkbl_complete' ) {

	my (@bl_list, $int_stream);

	# Create list of baselines created
	listbaselines();

	# Get name of the projects integration stream
	$int_stream = get_integration();

	my $bl_stream = "stream:$ENV{CLEARCASE_STREAM}";
	$log->information("Baseline stream name is [$bl_stream]");

	# The baseline(s) are on the integration stream so we are done
	if ( $int_stream eq $bl_stream ) {
		$log->information("Exit early & happy, the baseline is created on integration stream");
		exit 0;
	}

	my $deliver_is_in_progress = $clearcase->IsInProgress( stream => $bl_stream, operation => "deliver" );

	if ($deliver_is_in_progress) {
		$log->information("No deliver operation is in progress from stream");
	}
	else {
	}

	unless ( scalar @r ) {
		my $msg = setwarn_msg();
		if ( defined( $ENV{CLEARCASE_CMDLINE} ) ) {
			$log->assertion_failed($msg);
		}
		else {
			qx(clearprompt yes_no -prompt \"$msg\"  -mask abort);
			exit 1;
		}
	}

	my $int_master = $clearcase->get_master_replica( object => "$int_stream" );

	if ($int_master) {
		$log->information("Integration stream's master replica (\$int_master) is $int_master");
	}
	else {
		$log->assertion_failed("Required value for Integration stream's master replica (\$int_master) is empty");
	}

	my $dev_master = $clearcase->get_master_replica( object => $bl_stream );

	if ($dev_master) {
		$log->information("Development stream's master replica (\$dev_master) is $dev_master");
	}
	else {
		$log->assertion_failed("Required value for Development stream's master replica (\$dev_master) is empty");
	}


	if ( $int_master eq $dev_master ) {

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

$log->assertion_failed( "$Scriptfile did not expect to end here at line " . __LINE__ );

################################### SUBS ###################################


sub get_integration {
	my $reply =	$clearcase->get_integration_stream( project => "project:$ENV{CLEARCASE_PROJECT}" );
	if ($reply) {
		$log->information("Integration stream is [$reply]");
	}
	else {
		$log->assertion_failed("Required value for Integration stream (\$reply) is empty");
	}
	return $reply;
}

sub listbaselines {
	# Create list of baselines created
	@bl_list = split( /\s+/, $ENV{CLEARCASE_BASELINES} );
	$log->assertion_failed("No baselines found") unless ( $#bl_list > -1 );

	foreach (@bl_list) {
		$_ = "baseline:$_";
	}
}

sub setwarn_msg {

	my $warnmessage = <<ENDMESSAGE;
This the Triggger $TRIGGER_NAME.

Delivery is already in progress for stream $ENV{CLEARCASE_STREAM},
so the baselines $ENV{CLEARCASE_BASELINES} 
can NOT be automatically  delivered.
Please wait for syncronization and deliver the baseline manually

ENDMESSAGE

	return $warnmessage;

}

sub deliver {

	my @to_be_delivered;
	foreach my $baseline (@bl_list) {

		# Check baseline(s) mastership
		my $bl_master = $clearcase->get_master_replica( object => $baseline );
		if ( $bl_master eq $dev_master ) {
			$log->information("Could change mastership of $baseline replica $int_master");
			push @to_be_delivered, $baseline;

			if ( $triggerconfig{ChgBaselineMasterShip} ) {

				# Only change master ship if enabled through configuration file
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
	$log->information("Value of \$forcedeliver is [$forcedeliver]");
	my $deliver_cmd = "deliver $forcedeliver -stream $ENV{CLEARCASE_STREAM} -baseline " . join( ',', @to_be_delivered );
	$clearcase->ct( command => $deliver_cmd );

}

__END__
