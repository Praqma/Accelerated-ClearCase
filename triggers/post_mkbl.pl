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
our $TRIGGER_NAME = "ACC_SET_BL_PLEVEL";

our %install_params = (
	"name"     => $TRIGGER_NAME,                      # The name og the trigger
	"mktrtype" => "-ucmobject -all -postop chbl ",    # The stripped-down mktrtype command
	"supports" => "pvob",                             # csv list of generic and/or custom VOB types (case insensetive)
	"comment" => "Sets same promotion level all baselines on rootless, composite component baselines on same stream" 
);

# File version
our $VERSION = "1.0";
our $BUILD   = "0";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#
#    $Scriptfile  version $VERSION\.$BUILD
#
#    This script is intended as ClearCase trigger script for the
#    $TRIGGER_NAME trigger.
#
#    Implement a development policy that eliminates the confusion that concurrent
#    deliveries or rebases can cause developers. Only one developer can deliver to
#    an integration stream at a time.
#
#    The logic is based on the work of David Baird, in his ucm_serial_delivery
#    trigger
#
#    This script supports self-install (execute with the -install
#    switch to learn more).
#
#    Read the POD documentation in the script for more details
#    Date:       2010-03-10
#    Author:     Jens Brejner, jbr\@praqma.net
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
2010-03-10  Jens Brejner   1st release prepared for Novo (version 1.0.1)
-------------------------  ----------------------------------------------

ENDREVISION

######################################## Basic trigger stuff ###############################################

our $clearcase = pcc->new;

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;

# Look for semaphore, respecting a local semaphore path via env. var.
our $semaphore_status = $thelp->enable_semaphore_backdoor();

#Enable the features in scriptlog

our $log = scriptlog->new;

warn "Got to remove test code\n";
my $devmode = 1;

if ($devmode) {
	my $f = "$ENV{TEMP}/$Scriptfile.LOG";
	-e ($f) && unlink $f;
	$log->set_logfile($f);
}

#Define either environment variable CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->conditional_enable();

#Define either environment variable CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
$log->set_verbose();
our $logfile = $log->get_logfile;

$log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
$log->information($semaphore_status);
$log->dump_ccvars();                            # Run this statement to have the trigger dump the CLEARCASE variables

########################### MAIN ###########################
exit 0 unless $ENV{CLEARCASE_OP_KIND} eq 'chbl';

my $plevel    = defined( $ENV{CLEARCASE_PROMOTION_LEVEL} ) ? "$ENV{CLEARCASE_PROMOTION_LEVEL}"     : 0;
my $stream    = defined( $ENV{CLEARCASE_STREAM} )          ? "stream:$ENV{CLEARCASE_STREAM}"       : 0;
my $baseline  = defined( $ENV{CLEARCASE_BASELINES} )       ? "baseline:$ENV{CLEARCASE_BASELINES}"  : 0;
my $component = defined( $ENV{CLEARCASE_COMPONENT} )       ? "component:$ENV{CLEARCASE_COMPONENT}" : 0;

$log->information(
	"\$plevel has value [$plevel]\n\$stream has value [$stream]\n\$baseline has value [$baseline]\n\$component has value [$component]\n");

unless ( $clearcase->is_rootless( component => "$component" ) ) {
	$log->information("The component [$component] has a root directory, nothing to do");
	exit 0;
}

#ok, it is rootless, is it composite
my @depends_on = $clearcase->get_dependants( baseline => $baseline );
unless ( scalar(@depends_on) ) {
	$log->information("No baselines depends on $baseline, nothing to do");
	exit 0;
}
foreach (@depends_on) {
	$log->information("Checking dependant baseline $_");
	my ( $dep_level, $dep_stream ) = split( /,/, $clearcase->ct( command => "describe -fmt %[plevel]p,%X[bl_stream]p $_" ) );
	$log->information("It's promotion level is $dep_level");
	$log->information("It was created at $dep_stream");
	next unless ( $stream eq $dep_stream );
	$log->information("Stream matches ...");
	if ( $plevel eq $dep_level ) {
		$log->information("The promotion level is already as set properly");
		next;    # for whatever reason the dependant's promotion level is already the proper value
	}
	else {
		my $cmd = "chbl -c \"Trigger $TRIGGER_NAME changed promotion level to $plevel\" -level $plevel $_";
		$log->information("The promotion level must be updated");
		$log->information("To execute: [ $cmd]");
		$clearcase->ct( command => $cmd );
	}
}
exit 1;

