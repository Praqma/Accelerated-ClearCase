
require 5.000;
use strict;

our( $Scriptdir, $Scriptfile );

BEGIN {
    $Scriptdir  = ".\\";
    $Scriptfile = $0;      # Assume the script is called from 'current directory' (no leading path - $0 is the file)
    $Scriptfile =~ /(.*\\)(.*)$/
      && do {
        $Scriptdir  = $1;
        $Scriptfile = $2;
      }                    # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}

use lib $Scriptdir. "..";

use praqma::scriptlog;
use praqma::trigger_helper;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME = "ACC_SERIAL_DELIVER";

our %install_params = (
    "name"     => $TRIGGER_NAME,                                           # The name og the trigger
    "mktrtype" => "-ucmobject -all -preop deliver_start,rebase_start ",    # The stripped-down mktrtype command
    "supports" => "pvob"                                                   # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION = "1.0";
our $BUILD   = "1";

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

my $verbose_mode = defined( $ENV{'CLEARCASE_TRIGGER_VERBOSE'} ) ? $ENV{'CLEARCASE_TRIGGER_VERBOSE'} : undef;
my $debug_on     = defined( $ENV{'CLEARCASE_TRIGGER_DEBUG'} )   ? $ENV{'CLEARCASE_TRIGGER_DEBUG'}   : undef;

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;

# Look for semaphore, respecting a local semaphore path via env. var.
our $semaphore_status = $thelp->enable_semaphore_backdoor();

#Enable the features in scriptlog
our $log = scriptlog->new;

#Define either environment variable CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->conditional_enable();

#Define either environment variable CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
$log->set_verbose();
our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
($logfile) && $log->information($semaphore_status);
($logfile) && $log->dump_ccvars;                              # Run this statement to have the trigger dump the CLEARCASE variables

########################### MAIN ###########################

# values from trigger environment
my $project    = $ENV{'CLEARCASE_PROJECT'};
my $stream     = $ENV{'CLEARCASE_STREAM'};
my $src_stream = $ENV{'CLEARCASE_SRC_STREAM'};

# pvob from project name
my ($pvob) = ( $project =~ m{\@(.+)$} );

# do not permit a delivery from a development stream to another project's
# integration stream
my ($src_proj) = split '\n', qx{cleartool lsstream -fmt "%[project]p" $src_stream};

if ( $project ne "$src_proj\@$pvob" ) {
    my ( $istream, $src_istream ) = split '\n', qx{cleartool lsproject -fmt "%[istream]p\\n" $project $src_proj\@$pvob};

    if ( $src_stream ne "$src_istream\@$pvob" and $stream eq "$istream\@$pvob" ) {
        $log->enable(1);
        $log->error("\n");
        $log->error("***Interproject deliveries from development streams\n");
        $log->error("***to another project's integation stream is prohibited.\n");
        $log->error("\n");
        exit 1;
    }
}

# first look for a rebase operation in the integration stream
my $rebase = qx{cleartool rebase -status -stream $stream};

my $baseline = ( $rebase =~ /\s+baseline:(.+)\@/ );

if ( $rebase !~ /No rebase in progress/ ) {    #        Rebase is in progress
    $log->enable(1);
    $log->error("A rebase is already in progress from '$baseline'. Please try again later.");
    exit 1;
}

# regex to find deliver activity
my $rx = 'deliver\.([^.]+)\.';

# get the last activity, and if it is a delivery, get the development stream
my @activities = map { chomp; $_ } grep { /^$rx/o } qx{cleartool lsactivity -short -in $stream};

# look at the three last delivery activities
for ( my $i = 0 ; scalar( @activities - $i ) and $i < 3 ; $i++ ) {
    my $activity = $activities[ $#activities - $i ];

    # get status of stream which originated the activity
    my ($ostream) = ( $activity =~ /$rx/o );
    my $delivery = qx{cleartool deliver -status -stream $ostream\@$pvob};

    # if the activity name is in the status, then the delivery
    # is in progress
    if ( $delivery =~ /$activity/ ) {
        my $colleague = qx(cleartool des -fmt %u activity:$activity\@$pvob);
        $log->enable(1);
        $log->error("***A deliver initiated by '$colleague' is already in progress from '$ostream'. \n***Please try again later.\n\n");
        exit 1;
    }
}

# no deliver or rebase found, normal exit
exit 0;
