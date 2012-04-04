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
	"supports" => "ccucm_supported",                                          # csv list of generic and/or custom VOB types (case insensetive)
	"comment"  => "Start deliver of remotely created development baselines"
);

# File version
our $VERSION = "1.0";
our $BUILD   = "1";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#
#    $Scriptfile  version $VERSION.$BUILD
#
#    This script is intended as ClearCase trigger script for the
#    $TRIGGER_NAME trigger.
#
#    If the promotion level of a composite baseline on a rootless componenent 
#    is changed, the new promotion level is propagated to the baselines 
#    it is directly depending on.
#    The propagation of promotion level is limited to baselines with the 
#    following criteria:
#    * The baseline must be on rootless component
#    * The baseline must be on the same stream as the "parent" baseline
#    
#    The trigger fires after the change baseline event
#
#    This script supports self-install (execute with the -install
#    switch to learn more).
#
#    Read the POD documentation in the script for more details
#    Date:       2012-03-03
#    Author:     Jens Brejner, jbrejner\@praqma.net
#    Copyright:  Praqma A/S
#    License:    GNU General Pulic License v3.0
#    Support:    http://launchpad.net/acc
#
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2012-04-03  Jens Brejner   Initial version (version 1.0.1)

----------  -------------  ----------------------------------------------

ENDREVISION

######################################## Basic trigger stuff ###############################################

our $clearcase = pcc->new();

#Enable the features in trigger_helper
our $thelp = trigger_helper->new();
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;

# Look for semaphore, respecting a local semaphore path via env. var.
our $semaphore_status = $thelp->enable_semaphore_backdoor();

#Enable the features in scriptlog

our $log = scriptlog->new();

if ( $ENV{COMPUTERNAME} eq "VM-JBR-CC2" ) {

	# My development environment - always debug
	$log->set_logfile("$ENV{TEMP}\\minfil.log");
	$log->enable(1);
	$log->set_verbose(1);

}
else {

	#Define either environment variable CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
	$log->conditional_enable();

	#Define either environment variable CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
	$log->set_verbose();
}

our $logfile = $log->get_logfile;
$log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
$log->information($semaphore_status);
$log->dump_ccvars();                            # Run this statement to have the trigger dump the CLEARCASE variables

exit 0 if ( $ENV{CLEARCASE_POP_KIND} eq lc('deliver_start') || $ENV{CLEARCASE_POP_KIND} eq lc('rebase_start') );

########################### MAIN ###########################
if ( $ENV{CLEARCASE_OP_KIND} eq 'mkbl_complete' ) {

	my @bl_list = split( /\s+/, $ENV{CLEARCASE_BASELINES} );
	$log->assertion_failed("No baselines found") unless ( $#bl_list > -1 );

	foreach (@bl_list) {
		$_ = "baseline:$_";
	}

	my $dev_stream = "stream:$ENV{CLEARCASE_STREAM}";
	$log->information("Baseline stream name is [$dev_stream]");

	my $int_stream = $clearcase->get_integration_stream( project => "project:$ENV{CLEARCASE_PROJECT}" );
	if ($int_stream) {
		$log->information("Integration stream is [$int_stream]");
	}
	else {
		$log->assertion_failed("Required value for Integration stream (\$int_stream) is empty");
	}

	if ( $int_stream eq $dev_stream ) {

		# Baseline is on integration stream, so we are done.
		$log->information("Exit early & happy, the baseline is created on integration stream");
		exit 0;
	}
	my $int_master = $clearcase->get_master_replica( object => "$int_stream" );

	if ($int_master) {
		$log->information("Integration stream's master replica (\$int_master) is $int_master");
	}
	else {
		$log->assertion_failed("Required value for Integration stream's master replica (\$int_master) is empty");
	}

	my $dev_master = $clearcase->get_master_replica( object => $dev_stream );

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

	}

	# Change baseline(s) mastership
	my @to_be_delivered;
	foreach my $baseline (@bl_list) {
		my $bl_master = $clearcase->get_master_replica( object => $baseline );
		if ( $bl_master eq $dev_master ) {
			$log->information("Must change mastership of $baseline replica $int_master");
			push @to_be_delivered, $baseline;
			$clearcase->ct( command => "chmaster -c \"Trigger $TRIGGER_NAME changed mastership for Promotion Level update\" $int_master $baseline" );
		}
		else {
			$log->information("Baseline mastership of $baseline is $bl_master");
		}
	}
	push @to_be_delivered, @bl_list unless ( $#to_be_delivered > -1 );
	my $deliver_cmd = "deliver -stream $ENV{CLEARCASE_STREAM} -baseline " . join  (',',  @to_be_delivered );
	# Start deliver of baseline to default target.
	$clearcase->ct( command => $deliver_cmd);
	
	exit 0;

}

print "Change to happy exit \n";
exit 1;


__END__
