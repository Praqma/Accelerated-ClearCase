
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
our $BUILD   = "2";

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
2010-06-02  Jens Brejner   Regex that extract stream name from activities
                           has trouble if stream name contains decimal numbers
-------------------------  ----------------------------------------------

ENDREVISION
print "Revision comment\n";

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

# Rebase cheaph is 'cheapes' we'll chech that first.

my $rebase = &run("cleartool rebase -status -stream $stream");

if ( $rebase !~ /No rebase in progress/ ) {    #        Rebase is in progress
    $log->enable(1);
    $log->error("*******A rebase operation is aready in progress. Details about the rebase:\n\n$rebase\n*******Please try again later.\n");
    exit 1;
}

# Deliver activities are named in the format deliver.<stream>.<YYYYMMDD>.<HHMMSS>
# regex to find deliver activity
my $rx = 'deliver\.([^.]+)\.';
# Version  1.0.2, try improved regex, accepts that a stream name can contain
# a decimals like in "our_release_2.0" - that will confuse the previous
# definition of $rx.
$rx = 'deliver\.(\S+)\.\d{8}\.\d{6}$';

# Get the delivery activities on the integration stream
#   cleartool desc -fmt \%[activities]p stream:$stream
# Is significantly faster than
#   cleartool lsactivity -short -in $stream
# But return value is a space separated string
my $delim = ' ';    # a single space;

my @activities = map { chomp; $_ } grep { /^$rx/o } split /$delim/, &run("cleartool desc -fmt \%[activities]p stream:$stream");

# look at the three last delivery activities
my $i = 0;
my $activity = pop (@activities);
while ( $activity && $i++ < 3 ) {

    # get status of stream which originated the activity
    my ($ostream) = ( $activity =~ /$rx/o );
    my $delivery = &run("cleartool deliver -status -stream $ostream\@$pvob");

    # if the activity name is in the status, then the delivery
    # is in progress
    if ( $delivery =~ /$activity/ ) {
        $log->enable(1);
        $log->error("*******A DELIVER OPERATION IS ALREADY IN PROGRESS. Details about the delivery:\n\n$delivery\n*******Please try again later.\n");
        exit 1;
    }
    $activity = pop (@activities);
}

# no deliver or rebase found, normal exit
exit 0;

sub run($$) {
    my $cmd         = shift;
    my $aslist      = shift;
    my $cmdex       = $cmd . ' 2>&1';
    my @retval_list = qx{$cmdex};
    my $retval_scl  = join '', @retval_list;
    $? && do {
        $log->enable(1);
        $log->error("The command: $cmd failed!.\nIt returned:\n$retval_scl\n");
    };
    return @retval_list if $aslist;
    return $retval_scl;
}
