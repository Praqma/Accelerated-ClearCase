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

our $TRIGGER_NAME = "ACC_RM_EMPTY_BR";                # The Trigger name is cached to it can be referenced in the header.

our %install_params = (
    "name"     => $TRIGGER_NAME,                                         # The name og the trigger
    "mktrtype" => "-element -all -postop uncheckout,rmbranch,rmver ",    # The stripped-down mktrtype command
    "supports" => "bccvob,ucmvob",                                       # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "1.1";
our $REVISION = "4";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as trigger script for the
#     $TRIGGER_NAME trigger.
#     The trigger runs after versions, reserved checkouts or branches has
#     beed removed from ClearCase (rmver, rmbranch and uncheckout) and
#     checks if the operation left an empty branch and if so, removes the
#     branch too. The trigger always updates the removed or uncheckedout
#     element if the view is a snapshot view.
#     This script supports self-install (execute with the -install
#     switch to learn more).
#     Read the POD documentation in the script for more details
#     Date:       2009-08-17                                            '
#     Author:     Lars Kruse, lak\@praqma.net
#     Copyright:  Praqma A/S
#     License:    GNU General Pulic License v3.0
#     Support:    http://launchpad.net/acc
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ---------------------------------------------------
2009-06-24  Lars Kruse     1st release prepared for Novo Nordisk (version 1.0.1)
2009-11-09  Lars Kruse     Making it compliant with the new trigger_helper
                           (version 1.1.2)
2009-11-25  Jens Brejner   Isolate POD in separate file (v1.1.3)
2010-05-24  Jens Brejner   Fix bug with vobtags that starts with digits. (v1.1.4)
------------------------------------------------------------------------------
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

##################
snap_load();

######### CHECK IF BRANCH IS EMPTY AND REMOVE IF NECESSARY ##############
if ( $ENV{CLEARCASE_OP_KIND} =~ /uncheckout|rmver/ ) {        #Check that the events that fired the trigger is of the kind we support (rmbranch is dealt with later!)

    # Get out if brtype is 'main' even if it was empty we wouldn't attempt to delete it
    exit 0 if ( $ENV{CLEARCASE_BRTYPE} eq 'main' );

    $ENV{'CLEARCASE_XPN'} =~ /(.*?)[\\\/](\d+)$/;             #split up to the element+branch part - and the the tailing integer;
    our $elem_br = $1;
    our $verno   = $2;

    # Get out if uncheckout isn't triggered by the zero-version
    if ( $ENV{'CLEARCASE_OP_KIND'} eq "uncheckout" ) {
        exit 0 unless ( $verno eq 0 );                        # Get out NOW - unless the version is the zero-version - then we'll nuke it.
    }

    # Get out if rmver doesn't leave an empty branch
    if ( $ENV{'CLEARCASE_OP_KIND'} eq "rmver" ) {
        exit 0 unless &br_is_empty($elem_br);                 # Get out NOW - unless the branch is empty - then we'll nuke it.
    }

    &nuke_br($elem_br);
    exit 0;
}

######### CHECK IF BRANCH IS CASCADING OFF AN EMPTY BRANCH ##############
if ( $ENV{CLEARCASE_OP_KIND} =~ /rmbranch/ ) {                #Check that the events that fired the trigger is of the kind we support

    # Get out if the parent branch is 'main'
    my @brs = split ( /[\\\/]/, $ENV{'CLEARCASE_ID_STR'} );    #split on delimers
    exit 0 if ( $brs[ $#brs - 1 ] eq 'main' );                 # check that our parent (the second-to-last) isn't main

    $ENV{'CLEARCASE_XPN'} =~ /(.*)[\\\/].+/;                   #Get the XPN to the parent branch of the element;
    my $elem_br = $1;

    &nuke_br($elem_br) if ( &br_is_empty($elem_br) );          # nuke it if it's empty
    exit 0;
}

# If the CLEARCASE_OP_KIND isn't recognized at this point, then we're off limits!
$log->warning("This script is triggered by an event which it was not originally designed to handle\t\tMaybe it's not installed correct?");
exit 1;                                                        # Error code 1 on a post-op trigger will automatically cause a warning.

####################################  SUBS   #################################################
sub br_is_empty ($) {
    my $elem_br       = shift;
    my $cmd           = "cleartool lsvtree -all \"$elem_br\"";
    my @vtree_elem_br = `$cmd`;
    if ($?) {                                                  # The lsvtree command failed!
        my $output = join ",", @vtree_elem_br;
        $log->error("The command: '$cmd' failed\n");
        exit 1;
    }

    # An empty branch has two element in total:
    #   1: The branch itself
    #   2: The zero-version on the branch
    # Thus, if the highest valid index of the array should is larget than 1, then the branch isn't empty
    if ( $#vtree_elem_br > 1 ) {
        return 0;                                              # There are more versions on the branch - return false
    }
    return 1;                                                  #Else it's true - the branch is empty!
}

sub nuke_br ($) {
    my $elem_br = shift;
    $elem_br =~ /.*\@\@(.+)/;
    $log->information_always("Trigger script ($Scriptfile) is removing empty branch:\n  $1\n");
    my $cmd = "cleartool rmbranch -force -c \"Automatic removal of empty branch by trigger ($Scriptfile)\" \"$elem_br\"";
    $log->information("Executing: $cmd\n");
    my $output = `$cmd`;
    if ($?) {                                                  # The rmbranch command failed!
        $log->error( "The command: '$cmd' failed:\n$output\nUnable to determine state of " . $ENV{CLEARCASE_BRTYPE} . "\n" );
        exit 1;
    }
    $log->information("Result was:\n\>\>\>\n$output\n\<\<\<\n");
    return 1;
}

sub snap_load {
    if ( $ENV{'CLEARCASE_VIEW_KIND'} eq 'snapshot' ) {         #update the element
        my $cmd = "cleartool update -log nul \"$ENV{'CLEARCASE_PN'}\"";
        $log->information("Executing: $cmd\n");
        my $output = `$cmd`;
        if ($?) {                                              # The update failed
            $log->error("The command: '$cmd' failed\n");
        }
        $log->information("Result was:\n\>\>\>\n$output\n\<\<\<\n");
        $ENV{CLEARCASE_XPN} =~ /.*\@\@(.+)/;
        $log->information_always("Loading the predecessor to the removed version:\n  $1\n");
    }
}
