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
our $TRIGGER_NAME = "ACC_NAMED_BRTYPES_ONLY";

our %install_params = (
    "name"     => $TRIGGER_NAME,                      # The name og the trigger
    "mktrtype" => "-element -all -preop mkbranch",    # The stripped-down mktrtype command
    "supports" => "nnDocVOB",                         # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "1.1";
our $REVISION = "3";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as ClearCase trigger script for the
#     $TRIGGER_NAME trigger.
#
#     This script is intended as trigger script (element -all)
#     on the mkbranch event. It monitors a list of approved branches
#     and requires that no branches are created except these.
#     Date:       2009-10-07
#     Author:     Lars Kruse, lak\@praqma.net
#     License:    GNU General Pulic License v3.0
#     Support:    http://launchpad.net/acc
#########################################################################
ENDHEADER

# Revision information
#########################################################################
my $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
2006-10-26  Lars Kruse     1st release prepared for Novo Nordisk
                           (version 1.0.1)
2009-11-12  Mikael Jensen+
            Lars Kruse     ACC-ified (version 1.1.2)
2009-11-24  Jens Brejner   v1.1.3. Isolate POD info in POD file
-------------------------------------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;
our $semaphore_status = $thelp->enable_semaphore_backdoor;

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable();                    #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose();                           #Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
$log->information($semaphore_status);
$log->dump_ccvars;                                            # Run this statement to have the trigger dump the CLEARCASE variables

### Allow CHECKOUTS ON CERTAIN BRANCHES ONLY ###
if ( ( $ENV{CLEARCASE_OP_KIND} eq "mkbranch" ) ) {            #Check that the events that fired the trigger are the ones we support
    my $regexp = "main";                                      # list of branches that are allowed to create "brtype|brtype|..."
    my $brtype = $ENV{'CLEARCASE_BRTYPE'};
    unless ( $brtype =~ /$regexp/ ) {
        $log->error( "ERROR \n...triggered by a [mkbranch $brtype] event.\n\n"
              . "You are about to create a branch that is not approved\n"
              . "The config spec of your view might be wrong!\n\n"
              . "Contact the Configuration Manager or ClearCase Admin to get help!" );
        exit 1;
    }
}
exit 0;

__END__

