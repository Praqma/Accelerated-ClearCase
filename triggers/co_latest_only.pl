require 5.000;
use strict;
our( $Scriptdir, $Scriptfile );

BEGIN {
    $Scriptdir  = ".\\";
    $Scriptfile = $0;      # Assume the script is called from 'current directory' (no leading path - $0 is the file)
    $Scriptfile =~ /(.*\\)(.*)$/
      && do { $Scriptdir = $1; $Scriptfile = $2; }    # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}
use lib $Scriptdir. "..";
use praqma::scriptlog;
use praqma::trigger_helper;

# if version being checked out is being created, we have nothing to do here.
exit 0 if ( $ENV{'CLEARCASE_ID_STR'} =~ /.*\\$ENV{'CLEARCASE_BRTYPE'}\\0$/ );

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME = "ACC_CO_LATEST_ONLY";

our %install_params = (
    "name"     => $TRIGGER_NAME,                      # The name og the trigger
    "mktrtype" => "-element -all -preop checkout",    # The stripped-down mktrtype command
    "supports" => "bccvob,ucmvob",                    # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "1.0";
our $REVISION = "6";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as ClearCase trigger script for the
#     $TRIGGER_NAME trigger.
#
#     On checkout the trigger checks if the element is the latest and
#     prompts the user for action if the is a newer version of the element.
#
#     This script supports self-install (execute with the -install
#     switch to learn more).
#
#     Read the POD documentation in the script for more details
#     Date:       2009-11-26
#     Author:     Lars Kruse, lak\@praqma.net
#     Copyright:  Praqma A/S
#     License:    GNU General Pulic License v3.0
#     Support:    http://launchpad.net/acc
#     Docs:       Goto http://wiki.praqma.net/acc
#                 and search for "acc_co_latest_only"
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  -----------------------------------------------------
2009-11-26  Lars Kruse     1st release prepared for Novo (version 0.1.1)
2009-12-02  Jens Brejner   Fix bug, fails on vob root (version 0.1.2), isolate
                           pod information in separate file.
2009-12-03  Jens Brejner   Fix bug, fails if checkout creates a branch (v0.1.3).
2009-12-28  Jens Brejner   Fix bug, first version on branch fails (v0.1.4).
2010-03-17  Jens Brejner   Allow unreserved checkouts (v0.1.5)
2010-06-03  Jens Brejner   Ignore files that do not exist.... (can happen due to
						   inadequate national characther set support in CC 2003.6
						   (v0.1.6)
----------  -------------  -----------------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;
our $semaphore_status = $thelp->enable_semaphore_backdoor;

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable();                    #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose;                             #Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
$log->information($semaphore_status);
$log->dump_ccvars;                                            # Run this statement to have the trigger dump the CLEARCASE variables

######### PREVENT CHECKOUT OF VERSIONS UNLESS THEY ARE LATEST ON THE BRANCH ##############

if ( ( $ENV{'CLEARCASE_VIEW_KIND'} eq "snapshot" ) && ( $ENV{'CLEARCASE_OP_KIND'} eq "checkout" ) ) {    #Check that the events that fired the trigger are the ones we support

	if  (-e  $ENV{'CLEARCASE_PN'}) {
    # Allow unreserved Checkouts, CLEARCASE_RESERVED is 1 if reserved, 0 if unreserved
    exit 0 if ( $ENV{'CLEARCASE_RESERVED'} eq 0 );

    # find on directory elements needs some filtering.
    my $dirswitch = ( lc( $ENV{'CLEARCASE_ELTYPE'} ) eq "directory" ) ? " -directory" : "";

    my $cmd    = "cleartool find \"" . $ENV{'CLEARCASE_PN'} . "\" $dirswitch -version version(...\\" . $ENV{'CLEARCASE_BRTYPE'} . "\\LATEST) -print 2>&1";
    my $latest = `$cmd`;
    chomp($latest);

    ( $? || ( $latest eq "" ) ) && do {
        $log->error( "The result of the execution was unexpected please report to ClearCase Admin\n" . "Execute:\n\>$cmd\n" . "Return value was:\n$latest\n" );
        exit 1;
    };

    if ( $latest ne $ENV{CLEARCASE_XPN} ) {
        $log->error( "YOUR version is not the LATEST version on the branch. Update your snapshot view and try again\n"
              . "   YOUR   version: [$ENV{CLEARCASE_XPN}]\n"
              . "   LATEST version: [$latest]\n" );
        exit 1;
    }
    }else{
    	# the file we where going to look at - is not anyway ???
    	# can be caused by Clearcase version 6 which doesn't have proper support for national characters
    	# or by for instance microsoft word, that always are working at a hidden copy of the file, in same dir...
    	$log->warning("Can not find the file $ENV{'CLEARCASE_PN'} ignoring\n")
    }
    exit 0;
}
__END__
