######################## STANDARD STUFF ##############################

require 5.001;

=head1 NAME

sidswap.pl - change primary owner or group of a ClearCase VOB.

=head1 SYNOPSIS

The script can replace the owner or primary group of a vob

Execute the script with -help switch to learn the syntax and usage.

=head1 DESCRIPTION

Changing the vob-owner or vob primary group usually involves several actions to
be executed. This script does them all, while checking as well as logging the progress
and results.

=head1 SUPPORT

Visit http://launchpad.net/acc to get help.

=cut

# Getting the script dir
our ( $Scriptdir, $Scriptfile );

BEGIN {
    if ( $0 =~ /(.*[\/\\])(.*)$/ ) {
        $Scriptdir  = $1;
        $Scriptfile = $2;
    } else {
        $Scriptdir  = ".";
        $Scriptfile = $0;
    }

    END {

        # global log file
        close LOGFILE;
    }
}

# Use clauses
use strict;
use lib "$Scriptdir..//..";
use praqma::scriptlog;
use Getopt::Long;
use File::Compare;
use Win32::TieRegistry( Delimiter => "#", ArrayValues => 0 );
my $pound = $Registry->Delimiter("/");

# File version
our $VERSION = "0.1";
our $BUILD   = "3";

# Log and monitor default settings (overwriteable at execution)
my $debug        = 0;    # Set 1 for testing purpose
my $verbose_mode = 0;

# Default setting 0-0-1 (script execution will generate NO output unless explicitly told to, but logs to default location [Temp dir]\view_q.pl.[PID].log

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$BUILD
#     Execute with -help switch to learn more
#
#     Date:       2009-09-12
#     Author:     Jens Brejner, Jens.Brejner\@praqma.net
#     Copyright:  Praqma A/S, Denmark
#     License:    GNU General Pulic License
#     Support:    http://launchpad.net/acc
#########################################################################

ENDHEADER

# Revision information
our $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
2009-09-12  Jens Brejner   1st release prepared for Grundfos. Version 0.1.1

-------------------------------------------------------------------------

ENDREVISION

# Usage information
my $usage = <<ENDUSAGE;
$Scriptfile  version $VERSION\.$BUILD

        $Scriptfile -vobtag VOBTAG -newgroup NEWGROUP -logdir LOGFOLDER
                      [-keepservices] [-no_other] [-dryrun] [-debug]

        $Scriptfile -help

ENDUSAGE

# Documentation
my $doc = <<ENDDOC;
$Scriptfile  version $VERSION\.$BUILD help.

-vobtag                 Required. The vobtag of the vob to process. The script
                        must run on the host of that vob, will exit if that
                        requirement is not fullfilled.

-logdir PATH            Required. The toplevel folder of all logging performed
                        by this script. The folder will be created if it does
                        not exist, requires path to be enclosed in quoation
                        marks if there a spaces in the path. $Scriptfile creates
                        a summary log-file named $Scriptfile.log in the root of
                        the log directory, as well as a folder for each
                        execution. So if the logfolder is defined as c:\\swaplog,
                        there will be a main log file called
                        c:\\swaplog\\$Scriptfile.log as well as a directory
                        named by the following pattern: VOBTAG_YYYYMMDDHHMMSS,
                        where HHMMSS is in 24-hour format.
-newgroup GROUP         Required. The qualified group name
                        ( like in DOMAIN\\groupname ) of the new group, that
                        will become the new primary group in the vob. If the
                        name includes spaces, the name must be enclosed in
                        quotation marks.

-help                   Get help with the script syntax(you are watching it now)

                        --- Auxiliary switches ---

-keepservices           Optional. Keep Clearcase services running. The default
                        is to stop and subsequently start the ClearCase services
                        while running the the fix_prot step as per Rational re-
                        commandations.

-no_other               Optional. This will remove any priveledges held by any-
                        body, but the owner and the new primary group, by doing
                        a "cleartool protect -chmod o= " on each object in the
                        vob. This option prolongs the processing time.
-dryrun                 Optional. Print findings, and suggested command lines,
                        but no execution
-debug                  Optional. Enable debugging, default is off

ENDDOC

### Global variables ###
my (
    $sw_debug,        # Enable debugging, default is off
    $sw_dryrun,       # print findings, and suggested command lines, but no execution
    $sw_help,         #
    $sw_keep,         # enable to avoid stop & start of services
    $sw_logdir,       # required, all logs will be written below this path
    $sw_newgroup,     # qualified new group name
    $sw_no_other,     # optional, process all elements and remove group other
    $sw_vobtag,       # required, the vobtag from the command line
                      #
    $utilhome,        # root of Clearcase utils folder, usually %CLEARCASEHOME%\etc\utils
    $credsutil,       # full path to Clearcase creds.exe
    $fixprot,         # full path to ClearCase fix_prot.exe
    $sidwalk,         # full path to ClearCase vob_sidwalk.exe
    $groupsid,        # SID of the new group
    $sum_log,         # The summary log, for each invocation, with the same
                      # logdir, this log will be appended
    $g_errcount,      # global error count, if it is not 0, processing will be stopped
    $log,             # Object for the scriptlogger.
    $locallogpath,    # path to the logging directory for this invocation
    $vobpath,         # Vob storage path, i.e. d:\vobs\vobtag.vbs
    @allcommands      # All commands to execute, in order
);

### main ###

validate_options();    # Check input options
initialize();          # Setup logging
createcommands();      # Establish all nessecary commands

foreach (@allcommands) { print "$_\n"; }

################################################################################
#######                          sub functions                         #########

sub getgroupsid ($) {

    # Use creds.exe to get the group SID.
    # input parameter is the domain group to look for
    # Return 0 if not found, else return the SID

    my $group      = shift;
    my $failstring = "No mapping between account names and security IDs was done.";
    my $sid;

    foreach (`"$credsutil" -g "$group" 2>&1`) {
        my $val = $_;
        if (/$failstring/i) {
            $sid = 0;
            last;    # No reason to continue
        } elsif (/^\s+SID:\s+/) {
            /(S[0-9\-]+)/;
            $sid = $1;
            last;
        }
    }

    return $sid;
}

sub ccservice ($) {

    # Either stop or start Clearcase Services
    # return array of the commands

    my $action = shift;

    #my @services = qw(ALBD LOCKMGR CCCREDMGR);
    my @services;
    foreach (qw(ALBD LOCKMGR CCCREDMGR)) {
        push @services, "net $action $_";
    }
    return @services;
}

sub localvobpath {

    # find vob storage in local file system
    my $path;
    my $serverpath = "Vob server access path: ";
    foreach (`cleartool lsvob -l $sw_vobtag`) {
        next unless /^$serverpath/;
        $path = substr $_, length($serverpath);
    }
    return $path;
}

sub createcommands {

    # Build all the commands to execute

    # stop services before fixprot
    push @allcommands, ccservice("stop") unless ($sw_keep);

    # fix storage
    my $cmd = "\"$fixprot\" -r -root -chgrp $sw_newgroup $vobpath";
    push @allcommands, $cmd;

    # start services after
    push @allcommands, ccservice("start") unless ($sw_keep);

    # create SID map
    $cmd = "\"$sidwalk\" $sw_vobtag $locallogpath\\map_original.txt";

    # get the current vobgroup
    my $originalgroup = `cleartool des -fmt %[group]p vob:$sw_vobtag`;
    $log->information("Vob original group found [$originalgroup]");
    $originalgroup =~ s/\\/\\\\/g;    # need to double  backslash for the pattern matcn in while to work

    #create mapfile
    my $originalmap = "$locallogpath\\map_original.txt";
    my $newmap      = "$locallogpath\\map_original.txt";
    $cmd = "\"$sidwalk\" $sw_vobtag \"$originalmap\" 2>&1";
    $log->information("Creating sidwalk map file $originalmap");

    foreach (`$cmd`) {
        $log->information("$_");
    }

    #modify mapfile
    $log->information("Modifying sidwalk map file, saving results in $newmap");
    open( INFILE,  " < $originalmap" ) or die "can't open $originalmap : $!";
    open( OUTFILE, " +> $newmap" )     or die "can't open $newmap : $!";

    while (<INFILE>) {
        if ( $_ =~ /^$originalgroup/i ) {
            $_ =~ s/IGNORE,,/$sw_newgroup,GLOBALGROUP,$groupsid/;
            $log->information("$_");
        }
        printf OUTFILE $_;
    }
    close OUTFILE;
    close INFILE;

    # OUTFILE must be different than the original, File::Compare::compare returns 0 if equal

    if ( compare( "$originalmap", "$newmap" ) ) {

        $log->error("Sidwalk mapfile $newmap is not different from the original");
        notsogood();
    }

    # prepare vob_sidwalk command to map the objects to the new SIDs:
    my $map_execute = "$locallogpath\\map_execute.txt";
    $cmd = "\"$sidwalk\" -map \"$newmap\" -execute $sw_vobtag \"$map_execute\" 2>&1";

    $log->information("command to map the objects to the new SIDs:");
    $log->information("$cmd");
    push @allcommands, $cmd;

    # prepare Run the vob_sidwalk command to remove the historical SIDs:
    my $map_delete = "$locallogpath \\map_delete . txt ";
    $cmd = " \"$sidwalk\" -delete_groups $sw_vobtag \"$map_delete\" 2>&1";
    $log->information("command to remove the historical SIDs:");
    $log->information("$cmd");
    push @allcommands, $cmd;

    #prepare Run the vob_sidwalk command to update the file system permissions:
    my $map_recover = "$locallogpath \\map_recover . txt ";
    $cmd = " \"$sidwalk\" -recover_filesystem $sw_vobtag \"$map_recover\" 2>&1";
    $log->information("command to update the file system permissions:");
    $log->information("$cmd");
    push @allcommands, $cmd;

    # prepare a describe on the VOB to verify the change:
    $cmd = " cleartool des -l vob : $sw_vobtag 2 > &1 ";
    $log->information(" describe on the VOB to verify the change : ");
    $log->information("$cmd");
    push @allcommands, $cmd;

###################

}

sub now_formatted {

    # Just a formatting of the current time

    # create a formatted string based on date and time for now
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    $year = $year + 1900;

    # format it after YYYYMMDDHHmmSS
    my $startstamp = sprintf( "%04d%02d%02d.%02d%02d%02d", $year, $mon, $mday, $hour, $min, $sec );
    $debug && print " Formatted time is : $startstamp \n ";
    return "$startstamp ";

}

sub notsogood {

    # print to summary log
    my $msg = now_formatted . " \tERROR Please investigate the file " . $log->get_logfile . " \n ";
    $g_errcount++;
    printf LOGFILE $msg;
}

sub preparelog {

    # define and prepare the local logging directory, which includes the global logging
    # return 0 on error (or ...

    # the local logging dir name is calc:
    # strip backslash from vobtag
    ( my $vobname = $sw_vobtag ) =~ s/\\//;

    my $startstamp = " _ " . now_formatted;
    $debug && print "$vobname$startstamp \n ";
    $locallogpath = "$sw_logdir \\$vobname$startstamp ";
    if ( !-e $locallogpath ) {
        my $cmd = " mkdir \"$locallogpath\"";
        `$cmd`;
        ( $? / 256 ) && die "Trouble creating Local logging directory \"$locallogpath\"\n";
    }
    return $locallogpath;
}

sub help_mode {
    defined($sw_help) && do { print $header. $revision . $usage . $doc; exit 0; };
}

sub validate_options {
    my %options = (
        "debug!"        => \$sw_debug,       # Enable debugging, default is off
        "dryrun!"       => \$sw_dryrun,      # print findings, and suggested command lines, but no execution
        "help|?"        => \$sw_help,        #
        "logdir=s"      => \$sw_logdir,      # required, all logs will be written below this path
        "newgroup=s"    => \$sw_newgroup,    # qualified new group name
        "no_other!"     => \$sw_no_other,    # optional, process all elements and remove group other
        "vobtag=s"      => \$sw_vobtag,      # required, must know which vob to process.
        "keepservices!" => \$sw_keep
    );

    # Look for invalid options.
    die "$usage" unless GetOptions(%options);
}

sub findutils {

    #Look in registry to find ClearCase installation directory, then look for utils dir
    #die if we fail else return the path of the utils directory

    my $homekey = 'LMachine/SOFTWARE/Atria/ClearCase/CurrentVersion//ProductHome';
    my $home    = $Registry->{"$homekey"}
      or die "Can't read $homekey key: $^E\n";
    $home = "$home\\etc\\utils";
    -d $home or die "Can't locate $home\n";
    return $home;

}

sub initialize {

    # Verify that we can operate

    # Early out conditions
    ## Only tested on windows
    unless ( $ENV{'OS'} =~ /^Windows/i ) {
        die "$Scriptfile has only been written for use on Windows platform, which we did not seem to find\n";
    }

    # present help if help was requested
    help_mode();

    # Enable debug mode if requested by switch
    $debug = $sw_debug ? defined($sw_debug) : 0;

    $g_errcount = 0;

    # Find required utilities.
    $utilhome = findutils();
    $debug && $log->information("Found ClearCase utils at \"$utilhome\"");
    $credsutil = "$utilhome\\creds.exe";
    !-e $credsutil && die "Failed locating creds.exe\n";
    $fixprot = "$utilhome\\fix_prot.exe";
    !-e $fixprot && die "Failed locating fix_prot.exe\n";
    $sidwalk = "$utilhome\\vob_sidwalk.exe";
    !-e $sidwalk && die "Failed locating vob_sidwalk.exe\n";

    # Are all required switches defined ?
    my $exitmsg;

    # vobtag is required
    $exitmsg = "You must specify a vobtag with the -vobtag switch\n$usage";
    die $exitmsg unless defined($sw_vobtag);

    # new group is required
    $exitmsg = "You must specify a new vob group with the -newgroup switch\n$usage";
    die $exitmsg unless defined($sw_newgroup);

    # log directory root is required
    $exitmsg = "You must specify a logdirectory with the -logdir switch\n$usage";
    die $exitmsg unless defined($sw_logdir);

    # Good to proceed...
    ##Set up local or detailed logging
    $locallogpath = preparelog();
    my $locallog = "$locallogpath\\sidswap.log";
    $log = scriptlog->new;
    $log->set_logfile("$locallog");
    $log->enable();

    ## Setup global, summary logging file name.
    $sum_log = "$sw_logdir\\sidswap_summary.log";
    if ( -e $sum_log ) {
        open( LOGFILE, ">> $sum_log" ) || die "can't open $sum_log: $!";
        printf LOGFILE "\n" . now_formatted . "\tStart processing vobtag $sw_vobtag\n";
        printf LOGFILE now_formatted . "\t- more information in $locallog\n";
    } else {
        open( LOGFILE, ">> $sum_log" ) || die "can't open $sum_log: $!";
        printf LOGFILE "$Scriptfile  version $VERSION\.$BUILD Summary Logfile\n";
        printf LOGFILE "\n" . now_formatted . "\tStart processing vobtag $sw_vobtag\n";
        printf LOGFILE now_formatted . "\t- more information in $locallog\n";
    }

    $log->information("Preparing to switch primary group for vob $sw_vobtag to $sw_newgroup");
    $sw_debug && $log->information("Found creds.exe at \"$credsutil\"");
    $sw_debug && $log->information("Found fix_prot.exe at \"$fixprot\"");
    $sw_debug && $log->information("Found vob_sidwalk.exe at \"$sidwalk\"");
    $sw_debug && $log->information("Found SID of group \"$sw_newgroup\" to be $groupsid");

    # Must be on vob host
    $exitmsg = "Computer $ENV{'COMPUTERNAME'} is not host for vob $sw_vobtag\n$doc";
    unless ( lc( $ENV{'COMPUTERNAME'} ) eq lc(`cleartool des -fmt %h vob:$sw_vobtag`) ) {
        $log->error("$exitmsg");
        notsogood();
        die $exitmsg;
    }

    # group must be fully qualified (DOMAIN\group)
    $exitmsg = "Group must be fully qualified, and we did not find any backslash in the group \"$sw_newgroup\"\n$usage";
    unless ( $sw_newgroup =~ /\\/ ) {
        $log->error("$exitmsg");
        notsogood();
        die $exitmsg;
    }

    # Group SID must be retrievable
    $exitmsg  = "Failed getting SID for group $sw_newgroup, check spelling, remember quotes if the name contains white space\"$sw_newgroup\"\n$usage";
    $groupsid = getgroupsid($sw_newgroup);
    unless ($groupsid) {
        $log->error("$exitmsg");
        notsogood();
        die $exitmsg;
    }

    # Must be able to find local vob path
    $exitmsg = "Failed determining local vob path of vobtag $sw_vobtag\n$usage";
    $vobpath = localvobpath();
    unless ($vobpath) {
        $log->error("$exitmsg");
        notsogood();
        die $exitmsg;
    }

    # Vob can not be locked, vob_sidwalk -execute will fail
    $exitmsg = "Vob $sw_vobtag is locked, can not continue\n$usage";
    $vobpath = localvobpath();
    if (`cleartool lslock vob:$sw_vobtag`) {
        $log->error("$exitmsg");
        notsogood();
        die $exitmsg;
    }
}
1;

##########################################################################
__END__
