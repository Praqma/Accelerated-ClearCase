require 5.000;
use strict;

BEGIN {

    # Ensure that the view-private file will get named back on rejection.
    END {
        rename( "$ENV{CLEARCASE_PN}.mkelem", $ENV{CLEARCASE_PN} )
          if $? && !-e $ENV{CLEARCASE_PN} && -e "$ENV{CLEARCASE_PN}.mkelem";
    }
}

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
our $TRIGGER_NAME = "ACC_STOP_TWIN";

our %install_params = (
    "name"     => $TRIGGER_NAME,                    # The name og the trigger
    "mktrtype" => "-preop lnname -element -all",    # The stripped-down mktrtype command
    "supports" => "bccvob,ucmvob",                  # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "1.0";
our $REVISION = "25";

my $verbose_mode = 0;    # Setting the verbose mode to 1 will print the logging information to STDOUT/ERROUT ...even it the log-file isn't enabled

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as ClearCase trigger script for the
#     $TRIGGER_NAME trigger.
#
#     The trigger prevents creation of evil twins in ClearCase.
#
#     This script supports self-install (execute with the -install
#     switch to learn more).
#
#     Read the POD documentation in the script for more details
#     Date:       2009-07-28
#     Author:     Jens Brejner, jbr\@praqma.net
#     Copyright:  Praqma A/S
#     License:    GNU General Pulic License v3.0
#     Support:    http://launchpad.net/acc
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2008-10-24  Jens Brejner   1st release prepared for Novo (version 0.1.1)
2009-01-16  Jens Brejner   2st release prepared for Novo (version 1.0.18)
                           Minor edits and cleanup after Novo internal
                           review.
2009-12-07  Jens Brejner   Isoloate POD information (v1.0.23)
2010-01-27  Jens Brejner   Escape "[" or "]" in regexp, remove review comments,
                           remove clearprompt (v1.0.24)
2010-02-22  Jens Brejner   Enable semaphore directory via environment variable.
                           Please see documentation for usage. (v1.0.25)
-------------------------  ----------------------------------------------

ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;
# Look for semaphore, respecting a local semaphore path via env. var.
our $semaphore_status = $thelp->enable_semaphore_backdoor($ENV{'CLEARCASE_USE_LOCAL_SEMAPHORE'});

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable();    #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose;             #Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
($logfile) && $log->information($semaphore_status);
($logfile) && $log->dump_ccvars;                              # Run this statement to have the trigger dump the CLEARCASE variables

if ( lc( $ENV{'CLEARCASE_OP_KIND'} ) eq "lnname" ) {          # continue only if operation type is what we are intended for..

    # Here starts the actual trigger code.
    my $case_sensitive = 1;                                   # 0 means Case IN-Sensitive name matching

    my ( $dir_delim, $possible_dupe, $dupver );
    my $viewkind = $ENV{'CLEARCASE_VIEW_KIND'};
    my $pathname = $ENV{'CLEARCASE_XPN'};
    my $sfx      = $ENV{'CLEARCASE_XN_SFX'} ? $ENV{'CLEARCASE_XN_SFX'} : '@@';

    if ( $ENV{'OS'} =~ /[Ww]indows/ ) {

        # Convert any "X:\view_tag\vob_tag\.\*" to "X:\view_tag\vob_tag\*"
        $pathname =~ s/\\.\\/\\/;
        $dir_delim = "\\";
    } else {
        $dir_delim = "/";
    }

    # split element name in dir and leaf
    my ( $parent, $element ) = acc::split_dir_file($pathname);
    my $parent_dna = "$parent.$sfx";

    # Are we in a snapshot view?
    my $snapview;
    if ( exists( $ENV{'CLEARCASE_VIEW_KIND'} )
        && $ENV{'CLEARCASE_VIEW_KIND'} ne 'dynamic' )
    {
        $snapview = 1;
    } else {

        # The 2nd test is a special case for the vob root.
        $snapview = !-e "$parent$sfx/main" && !-e "$parent/$sfx/main";
    }

    $log->information("Snapview ? $snapview\n");

    my $found = 0;
    my $pattern;    # Casesensitive search pattern - or not

    if ($case_sensitive) {
        $pattern = "$element";
    } else {
        $pattern = "(?i)$element";
    }

    # Need to escape square brackets, as this string will be used as a regexp.
    $pattern =~ s/\[|\]/\\$&/g;

    ($logfile) && $log->information("The Search pattern looks like:\'$pattern\'\n");

    # get lines from lshist that begins with either added or uncat and ends with digit
    my @lines = grep { /^added.*?$element.*\\\d+$|^uncat.*?$element.*\\\d+$/i } qx(cleartool lshist -nop -min -nco -dir -fmt "%Nc%Vn\\n" "$parent_dna");
    chomp @lines;

    my %added        = ();    #  table of latest version where NAME was added
    my %uncatalogued = ();    #  table of latest version where NAME was seen before uncatalogue

    foreach (@lines) {

        # isolate elementname and branch version
        my ( $action, $name, $junk, $branch ) = /(.*")(.*)("\.)(.*)/;

        # Fill table of latest version where file was added
        if (/^Added/i) {
            $added{$name} = $branch unless $added{$name};
        }

        # Fill table of latest version where NAME was seen before uncatalog
        if (/^Uncat/i) {

            # chop branch and version number
            my ( $b, $v ) = ( $branch =~ /(.*)(\d+)/ );
            $v--;    # decrement version number
            my $lastknown = "$b$v";
            $uncatalogued{$name} = $lastknown unless $uncatalogued{$name};
        }
    }

    my @match = grep /^$pattern$/, keys %added;

    if (@match) {
        $dupver = $match[$#match];

        $found = $dupver;

    }

    # No duplicate element is found on invisible branches
    # Allow the creation of the element.
    exit 0 unless $found;

    $log->enable();
    $log->set_verbose($verbose_mode);
    my $user      = "$ENV{'CLEARCASE_USER'}";
    my $pop_kind  = "$ENV{'CLEARCASE_POP_KIND'}";
    my $vob_owner = `cleartool desc -fmt %u vob:$ENV{'CLEARCASE_VOB_PN'}`;

    my $prompt = " Trigger $TRIGGER_NAME prevented operation [$pop_kind]\n";
    $prompt = "$prompt because an evil twin possibility was detected:\n\n";

    if ( $pop_kind eq "mkelem" ) {

        # From a mkelem command
        $prompt = "$prompt The name: [$element]\n";

    } else {

        # From a "ln", "ln -s" or "mv" command
        if ( !$pop_kind || ( $pop_kind eq "rmname" ) || ( $pop_kind eq "mkslink" ) ) {

            $log->information( "DEBUG\tLine " . __LINE__ . " Operation is not mkelem, but $pop_kind\n" );
            $prompt = "$prompt The element name [$element]\n";

        }
    }

    $prompt = "$prompt ALREADY exists for the directory:\n [$parent]\n";
    $prompt = "$prompt That name was added in branch version:\n";
    $prompt = "$prompt [$added{$element}].\n";
    $prompt = "$prompt \n";

    # check if it has been uncatogued
    chomp( my @lastseen = grep /$pattern$/, keys %uncatalogued );

    if (@lastseen) {
        $prompt = "$prompt The name has last been seen in: \n";
        $prompt = "$prompt [$uncatalogued{$element}].\n";
        $prompt = "$prompt \n";
    }

    $prompt = "$prompt NOTE:  If you feel you really need to perform this action\n";
    $prompt = "$prompt e-mail the VOB_OWNER ($vob_owner).\n\n";

    foreach ( split ( /\n/, $prompt ) ) {
        $log->warning("$_\n");
    }

    $prompt = "$prompt Action is logged in logfile:\n " . $log->get_logfile . "\n";
    print $prompt;

    # prevent the operation
    exit 1;

}    #

__END__
