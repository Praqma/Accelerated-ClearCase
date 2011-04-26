require 5.000;
use strict;
our ( $Scriptdir, $Scriptfile );

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
use File::Basename;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME = "ACC_BLOCK_RMNAME_IF_CO";

our %install_params = (
    "name"     => $TRIGGER_NAME,                     # The name og the trigger
    "mktrtype" => "-element -all -preop rmname ",    # The stripped-down mktrtype command
    "supports" => "bccvob,ucmvob",                   # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "0.1";
our $REVISION = "2";

my $verbose_mode = 1;

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as trigger script for the
#     $TRIGGER_NAME trigger.
#     The trigger runs before rmname on an element
#     The user cannot rmname if the file is checked out.
#     This script supports self-install (execute with the -install
#     switch to learn more).
#     Read the POD documentation for more details
#     Date:       2011-04-05
#     Author:
#     Copyright:  Praqma A/S
#     License:    GNU General Pulic License v3.0
#     Support:    http://launchpad.net/acc
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR             NOTE
----------  -----------------  ---------------------------------------------------
2011-04-26  Jens Brejner       Add external config so parent folder can be considered.
2011-04-05  Margit Bennetzen   Script added to acc (v0.1)
------------------------------------------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;
our $semaphore_status = $thelp->enable_semaphore_backdoor;

# Enable external configuration options
my %twincfg;
$thelp->get_config( \%twincfg );

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable();    #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->enable(1);
$log->set_verbose(1);          #Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
$log->information($semaphore_status);
$log->dump_ccvars;                                            # Run this statement to have the trigger dump the CLEARCASE variables

# Vob symbolic links can not be renamed.
exit 0 if -l $ENV{CLEARCASE_PN};

my ( $msg, $element );

# Only process if proper OP_KIND
if ( $ENV{CLEARCASE_OP_KIND} eq "rmname" ) {

    if ( $twincfg{AlsoParent} ) {
        $element = dirname( $ENV{CLEARCASE_PN} );
        $msg     = "You cannot rename the element [" . basename( $ENV{CLEARCASE_PN} ) . "] because it's parent folder is checked out by ";
        $log->information("Calling from Alsoparent, Element is [$element]");
        check_co();
    }

    $element = $ENV{CLEARCASE_PN};
    $msg     = "You cannot rename the element [" . basename( $ENV{CLEARCASE_PN} ) . "] because it is checked out by ";
    $log->information("Calling after Alsoparent, Element is [$element]");
    check_co();
    exit 0;
}

sub check_co {
    my @co_info = qx(cleartool lscheckout -directory -fmt "%Tf,%u\n" "$element");
    if ( scalar(@co_info) ) {
        foreach (@co_info) {
            my ( $view, $user ) = split( /,/, $_ );

            # Our own view is OK.
            next if ( $view eq $ENV{CLEARCASE_VIEW_TAG} );

            $log->enable(1);
            $log->error("$msg $user in view $view");
            exit 1;
        }
    }

}

__END__

