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
our $TRIGGER_NAME = "ACC_PRE_SETACT";

our %install_params = (
    "name"     => $TRIGGER_NAME,                                       # The name og the trigger
    "mktrtype" => "-ucmobject -all -preop mkactivity,setactivity ",    # The stripped-down mktrtype command
    "supports" => "pvob"                                               # csv list of generic and/or custom VOB types (case insensetive)
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
#    Prevents developers from creating non-delivery and non-rebase activities
#    on integration streams, and from reusing delivery and rebase activities.
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

my $cmd;
my $op_kind    = $ENV{'CLEARCASE_OP_KIND'};
my $user       = lc( $ENV{'CLEARCASE_USER'} );                # lowercase, facilitates matching later.
my $project    = "project:" . $ENV{'CLEARCASE_PROJECT'};
my $thisstream = "stream:" . $ENV{'CLEARCASE_STREAM'};
$cmd = "cleartool lsproj -fmt \%[istream]Xp\\n\%NS[" . acc::ATTYPE_UCM_INTEGRATORS . "]a $project";
my ( $istream, $integrators ) = qx($cmd);

if ( $op_kind =~ /mkactivity|setactivity/ ) {

    # Don't think if initiated by rebase_start or deliver_start
    exit 0 if ( &is_okpopkind( $ENV{'CLEARCASE_POP_KIND'}, "^rebase_start|^deliver_start" ) );

    # Don't think if user is an integrator
    exit 0 if ( ( defined($integrators) ) && &is_integrator( $user, $integrators ) );

    # $ENV{'CLEARCASE_ACTIVITY'} is only available for pre-op triggers when op-kind is setactivity
    my $activity = defined( $ENV{'CLEARCASE_ACTIVITY'} ) ? $ENV{'CLEARCASE_ACTIVITY'} : undef;

    if ( defined($activity) ) {    # operation is setactivity
    # On dev streams, test activity name against naming regex, IF such exists for that projet
        my $pattern;
        my $cmd = "cleartool des -fmt \%NS[" . acc::ATTYPE_ACTIVITY_NAME_TEMPLATE . "]a $project";
        $debug_on && $log->information("Query attribute value by calling [$cmd]\n");
        $pattern = qx($cmd);
        $pattern =~ s/(^"|"$)//g;    # No lead- or trailing quote.
        $pattern && exit 1 unless ( &is_validname( $activity, $pattern ) );
        exit 0;

    } else {                         # operation is mkactivity
        if ( &is_intstream( $project, $thisstream ) ) {

            # with project model = simple there's only one stream, which then also is the integration
            # stream. For these projects any activity name is valid (well if there isn't a name policy)
            my $projectmodel = "SIMPLE";
            if ( (qx (cleartool lsproj -fmt %[model]p $project)) =~ /^$projectmodel$/i ) {
                $log->information("Project model of $project is $projectmodel\n");
                exit 0;
            }
            $log->enable(1);
            $log->error("It is prohibited to create activities in an integration stream.\n");
            exit 1;
        }

    }
    exit 0;
} else {
    $log->enable(1);
    $log->error("Trigger fired out of expected context, Please contact administrator\n ");
    exit 1;
}

########################### SUBS ###########################

sub is_validname ($$) {

    #    Determines if the activity is valid for the project
    #
    #    Inputs:
    #    1'st input is the activitiy name
    #    2'nd input is the pattern to match against
    #
    #    Returns 1 if the name is valid
    #    Returns 0 if is not valid

    my $name    = shift;
    my $pattern = shift;
    if ( $name !~ /$pattern/ ) {
        $log->enable(1);
        $log->error("The activity name $name is prohibited in $project\n");
        $log->error("because it does not match the regex /$pattern/\n");
        $log->error("You can run cleartool rmact $ENV{'CLEARCASE_ACTIVITY'} to delete it\n");
        return 0;
    }

    $debug_on && $log->information("Activity name $name is legal, exiting trigger happily\n");
    return 1;
}

sub is_intstream ($$) {

    #    Determines if the current stream is an integration stream
    #
    #    Inputs:
    #    1'st input is the project qualifier
    #    2'nd input is the current stream selector
    #
    #    Returns 1 if the current stream is the integration stream of the project
    #    Returns 0 if is the current stream is not an integration stream.

    my $project = shift;
    my $stream  = shift;
    my $istream = qx(cleartool lsproj -fmt %[istream]Xp $project);
    chomp($istream);

    $debug_on && do {

        $log->information("Project integration stream of [$project] is [$istream] \n");
        $log->information("Current stream is [$istream] \n");
    };

    if ( $stream eq $istream ) {    # Current stream is the integration stream
        return 1;
    }
    $debug_on && $log->information("Not exiting due to not integration stream\n");
    return 0;
}

sub is_integrator ($$) {

    # Early out if user is integrator (see documentation)
    # Let integrators do anything
    #
    # Each project can have one or more special users specified, and theses persons
    # are not stopped by the trigger.
    # Their user profiles will be in a string atttibute value attached to the project

    # Inputs:
    # 1'st input is the current user
    # 2'nd input is the attribute value
    #
    # Returns 1 if the user is matched against the attribute value
    # Retruns 0 if is not, or attribute value is empty

    my $user = shift;
    return 0 unless my $attrvalue = shift;    # If there is no value, we have noting to do here.

    $attrvalue =~ s/(^"|"$)//g;               # No lead- or trailing quotes.
    if ( grep { /$user/i } split /;/, $attrvalue ) {    # is current user one of the integrators ?
        $debug_on && do {
            $log->information( "User " . $ENV{'CLEARCASE_USER'} . " is an integrator on $project so script will exit now\n" );
        };
        return 1;
    }
    $debug_on && $log->information("Not exiting because of integrator\n");
    return 0,;
}

sub is_okpopkind ($$) {

    # Early out if caused by rebase_start or deliver_start
    #
    # If Parent Operation Kind ()is either "rebase_start" or "deliver_start"
    # then exit without further interference
    # Inputs:
    # 1'st input is the pop_kind
    # 2'nd input is a regex of accepted values
    # Returns 1 if the CLEARCASE_POP_KIND is accepted values
    # Retruns 0 if is not

    my $parent_op_kind  = shift;
    my $earlyoutpattern = shift;
    if ( $parent_op_kind =~ /$earlyoutpattern/i ) {
        $debug_on && do {
            $log->information("CLEARCASE_POP_KIND value is $parent_op_kind\n");
            $log->information("CLEARCASE_POP_KIND was mathching the pattern $earlyoutpattern, script will exit now\n");
        };
        return 1;
    }

    $debug_on && $log->information("Not exiting on parent op kind\n");
    return 0;
}

