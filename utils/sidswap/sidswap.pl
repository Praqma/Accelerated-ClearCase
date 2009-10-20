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

    $log,             # Object for the scriptlogger.
    $locallogpath,    # path to the logging directory for this invocation
    $vobpath,         # Vob storage path, i.e. d:\vobs\vobtag.vbs
    @allcommands      # All commands to execute, in order
);

### main ###

validate_options();    # Check input options
initialize();          # Setup logging
createcommands();      # Establish all nessecary commands

foreach (@allcommands) {print "$_\n";}

################################################################################
#######                          sub functions                         #########



sub getgroupsid ($){
# Use creds.exe to get the group SID.
# input parameter is the domain group to look for
# Return 0 if not found, else return the SID

my $group = shift ;
my $failstring = "No mapping between account names and security IDs was done.";
my $sid;

foreach (`"$credsutil" -g "$group" 2>&1`){
	my $val = $_;
	if (/$failstring/i) {
    	$sid = 0;
    	last; # No reason to continue
	}elsif (/^\s+SID:\s+/) {
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

    my $action   = shift;
    #my @services = qw(ALBD LOCKMGR CCCREDMGR);
    my @services;
    foreach (qw(ALBD LOCKMGR CCCREDMGR)) {
        push @services, "net $action $_";
    }
    return    @services;
 }

sub localvobpath{
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
	push @allcommands, cmd;
    # start services after
    push @allcommands, ccservice("start") unless ($sw_keep);
    # create SID map
    $cmd = "\"$sidwalk\" $sw_vobtag $locallogpath\\sidmap1.txt";
   	push @allcommands, $cmd;

 }

sub now_formatted {

    # Just a formatting of the current time

    # create a formatted string based on date and time for now
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    $year = $year + 1900;

    # format it after YYYYMMDDHHmmSS
    my $startstamp = sprintf( "%04d%02d%02d.%02d%02d%02d", $year, $mon, $mday, $hour, $min, $sec );
    $debug && print "Formatted time is: $startstamp\n";
    return "$startstamp";

}

sub notsogood {
# print to summary log
my $msg = now_formatted . "\tERROR Please investigate the file " . $log->get_logfile . "\n";
printf LOGFILE  $msg;
}


sub preparelog {

    # define and prepare the local logging directory, which includes the global logging
    # return 0 on error (or ...

    # the local logging dir name is calc:
    # strip backslash from vobtag
    ( my $vobname = $sw_vobtag ) =~ s/\\//;

    my $startstamp = "_" . now_formatted;
    $debug && print "$vobname$startstamp\n";
    $locallogpath = "$sw_logdir\\$vobname$startstamp";
    if ( !-e $locallogpath ) {
        my $cmd = "mkdir \"$locallogpath\"";
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

    # Find required utilities.
    $utilhome = findutils();
    $debug && $log->information("Found ClearCase utils at \"$utilhome\"");
    $credsutil = "$utilhome\\creds.exe";
    !-e $credsutil && die "Failed locating creds.exe\n";
    $fixprot = "$utilhome\\fix_prot.exe";
    !-e $fixprot && die "Failed locating fix_prot.exe\n";
    $sidwalk  = "$utilhome\\vob_sidwalk.exe";
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
    $sw_debug &&     $log->information("Found fix_prot.exe at \"$fixprot\"");
    $sw_debug &&     $log->information("Found vob_sidwalk.exe at \"$sidwalk\"");
    $sw_debug &&     $log->information("Found SID of group \"$sw_newgroup\" to be $groupsid");
    # Must be on vob host
    $exitmsg = "Computer $ENV{'COMPUTERNAME'} is not host for vob $sw_vobtag\n$doc";
	unless ( lc( $ENV{'COMPUTERNAME'} ) eq lc(`cleartool des -fmt %h vob:$sw_vobtag`) ){
		$log->error("$exitmsg");
	    notsogood() ;
    	die $exitmsg
    }

    # group must be fully qualified (DOMAIN\group)
    $exitmsg = "Group must be fully qualified, and we did not find any backslash in the group \"$sw_newgroup\"\n$usage";
    unless ($sw_newgroup =~ /\\/){
		$log->error("$exitmsg");
	    notsogood() ;
    	die $exitmsg
    }
    # Group SID must be retrievable
    $exitmsg = "Failed getting SID for group $sw_newgroup, check spelling, remember quotes if the name contains white space\"$sw_newgroup\"\n$usage";
    $groupsid = getgroupsid($sw_newgroup);
    unless ($groupsid){
		$log->error("$exitmsg");
	    notsogood() ;
    	die $exitmsg
    }
    # Must be able to find local vob path
    $exitmsg = "Failed determining local vob path of vobtag $sw_vobtag\n$usage";
    $vobpath = localvobpath();
    unless ($vobpath){
		$log->error("$exitmsg");
	    notsogood() ;
    	die $exitmsg
    }





}

##########################################################################
__END__

## The rest is old script

#our %stg_directory;
#our $log = scriptlog->new;
#our $view_q_file=".view_quarantine";
#our $view_q_ignore_file=".view_q_ignore";
#our ($sw_lsquarantine, $sw_recover, $sw_purge, $sw_nasince, $sw_quarantine, $sw_autoquarantine,
#     $sw_autopurge, $sw_help, $sw_region, @sw_ignore, @sw_noignore, $sw_autorecover, $sw_logfile, $sw_verbose, $sw_debug);
#our $argstring;
#if (@ARGV) {
#    foreach (@ARGV) {
#        $argstring = $argstring . "$_ ";
#    }
#}

#validate_options();

##### SWITCH ####
#help_mode();
#enable_log();
#recover_mode();
#lsquarantine_mode();
#purge_mode();
#nasince_mode();
#quarantine_mode();
#ignore_mode();
##### SWITCH ####
#$log->assertion_failed("Wrong syntax\n".$usage);
############################################################################################

#=head1 Script Implementation

#=head2 Internal subfunctions

#=head3 validate_options( )

#The sub-functions read the options and switches applied with the execution into
#the global variables that are defined to cache them.

#The function will kill the script execution if unknown switches are used.

#Parameters:

#  none

#Returns:

#  nothing

#=cut

#sub validate_options(){
#  my %options = ( "autoquarantine"     => \$sw_autoquarantine,
#                  "lsquarantine"       => \$sw_lsquarantine,
#                  "nasince=s"          => \$sw_nasince,
#                  "help"               => \$sw_help,
#                  "quarantine=s"       => \$sw_quarantine,
#                  "recover=s"          => \$sw_recover,
#                  "purge=s"            => \$sw_purge,
#                  "autopurge"          => \$sw_autopurge,
#                  "autorecover"        => \$sw_autorecover,
#                  "ignore=s"           => \@sw_ignore,
#                  "noignore=s"         => \@sw_noignore,
#                  "region=s"           => \$sw_region,
#                  "logfile!"           => \$sw_logfile,
#                  "debug!"             => \$sw_debug,
#                  "verbose!"           => \$sw_verbose);

##  die "$usage" unless GetOptions(%options);
#  GetOptions(%options);
#};

#=head3 enable_log( )

#The sub-function overwrites the default settings for log, debug and verbose if set manually and enables the functionality in the logger.
#Prefix option name with "no" for force disable (e.g. -nodebug)

#Debug:
#- enables verbose, unless -noverbose is set in the script call.
#- enables the logfile
#- gives some extra logging information (variable values, additional information, ect.)

#Verbose:
#- enables log to STDOUT

#Logfile:
#- enables the logfile
#- sets the logfilename (and path) if specified
#- the environment variables SCRIPTLOG_ENABLED or CLEARCASE_TRIGGER_DEBUG forces the logfile to enable, not matter what

#Checks for ARGV arguments (unreferenced values):
#- if log is enabled, it dies if there is more then one (expect it to be filename or relative/absolute path AND filename)
#- if log is disabled, it dies if there are any
#- The logger module fails, if the specified log, can't be opened/created

#Parameters:

#  Non
#  Uses -verbose, -debug and -logfile

#Returns:

#  nothing (unless it dies)

#exit:

#  Will kill the script exit 1 (die) on ARGV errors - printing the arguments

#=cut

#sub enable_log(){

#    # Overwrites the default logging setting, if set manually
#    defined($sw_debug) && do {$debug=$sw_debug} && ($verbose_mode=1);
#    defined($sw_verbose) && do {$verbose_mode=$sw_verbose};
#    defined($sw_logfile) && do {$log_enabled=$sw_logfile};

#    my $argv_values;
#    foreach (@ARGV) {
#        $argv_values = $argv_values."\"".$_."\" "; #rw2 use join

#    }

#    # Checks ARGV for consistency and enables the log
#    if ($log_enabled) {
#        if (scalar(@ARGV) gt 1) {
#            $log->assertion_failed("You have more then one value with no defined reference,\nonly valid option is logfile location \nRecorded values are:$argv_values")
#        }
#        $log->set_logfile($ARGV[0]);
#        $log->enable();
#    } else {
#        if (scalar(@ARGV) gt 0) {
#            $log->assertion_failed("You have value(s) with no defined reference,\nRecorded values are: $argv_values")
#        } # end if scalar(argv)
#        $log->conditional_enable();
#    } # end if logfile

#    # Sets verbose
#    $verbose_mode
#      && do {
#        $log->set_verbose(1);
#        $log->information("Verbose is ON\n");
#      };

#    # Sets debug
#    $debug
#      && do {
#        $log->enable();
#        $log->set_verbose(1);
#        $log->information("DEBUG is ON\n");
#        #rw2 subject for revision: dynamic dump of sw_options (for each key in %options)
#        $log->information("Dumping all switch variables \n autoq = '$sw_autoquarantine' \n lsq = '$sw_lsquarantine' \n nas = '$sw_nasince' \n help = '$sw_help' \n quaran = '$sw_quarantine' \n recov = '$sw_recover' \n purge = '$sw_purge' \n autop = '$sw_autopurge' \n autor = '$sw_autorecover' \n igno = '@sw_ignore' \n reg = '$sw_region' \n noigno = '@sw_noignore' \n reg = '$sw_region' \n log = '$sw_logfile'+".$log->get_logfile()." \n debug = '$sw_debug' \n ver = '$sw_verbose' \n ARGV = $argv_values \n");
#        $log->information("ARGV value checks OK");
#      };
#    $log->information("Called with ".$argstring."\n");
#}

#=head3 xxx_mode( )

#The sub-functions named xxx_mode all work as switches.

#They all start by checking the options and switches applied with the execution to see if the have any work
#to do. if so, they take full responsibility over the remainder of the script execution and exits the script
#with either 1 or 0;

#Parameters:

#  none

#Returns:

#  nothing

#exit:

#Will force the entire script to exit with 0 or 1

#  1  =   Wrong set of switches applied
#  0  =   Successful execution

#=cut

#sub help_mode(){
#  defined($sw_help) && do {print $header.$revision.$usage.$doc; exit 0;};
#};

#sub recover_mode(){
#  defined($sw_recover) && do {
#    $log->information("recover\n");
#    if (  defined($sw_lsquarantine) || defined($sw_purge) || defined($sw_nasince) ||
#       defined($sw_quarantine) || defined(@sw_ignore) ||
#       defined($sw_autoquarantine) || defined($sw_autopurge)  || defined($sw_region) || defined($sw_autorecover)
#    ) {
#        $log->assertion_failed("Wrong syntax\n".$usage);
#    };
#    chomp($sw_recover);
#    if (recover_stg($sw_recover)) {
#        $log->information("View \"$sw_recover\" was recovered succesfully\n");
#    } else {
#        $log->error("View \"$sw_recover\" was NOT recovered\n");
#    }
#    exit 0;
#  };
#}

#sub lsquarantine_mode(){
#  defined($sw_lsquarantine) && do {
#    $log->information("lsquarantine\n");
#    (  defined($sw_purge) || defined($sw_nasince) || defined($sw_quarantine) || defined(@sw_ignore) ||
#       defined($sw_autoquarantine) || defined($sw_region)
#    ) && do {$log->assertion_failed("Wrong syntax\n".$usage);};
#    (  defined($sw_autorecover) && defined($sw_autopurge) ) && do {$log->assertion_failed("-autopurge and -autorecover can't be used together\n".$usage);};
#    foreach (lsquarantined() ){
#      $log->information($_);
#      defined($sw_autopurge) && do {
#         purge_stg($_);
#      };
#      defined($sw_autorecover) && do {
#        if (recover_stg($_)) {
#          $log->information("View was recovered succesfully\n");
#        } else {
#          $log->error("View was NOT recovered\n");
#        }
#      };
#    }
#    exit 0;
#  };
#}

#sub purge_mode(){
#  defined($sw_purge) && do {
#    $log->information("purge\n");
#    (  defined($sw_nasince) || defined($sw_quarantine) || defined(@sw_ignore) ||
#       defined($sw_autoquarantine) || defined($sw_autopurge) || defined($sw_region)  || defined($sw_autorecover)
#    ) && do {$log->assertion_failed("Wrong syntax\n".$usage);};
#    purge_stg($sw_purge);
#    exit 0;
#  };
#}

#sub nasince_mode(){
#  defined($sw_nasince) && do {
#    $log->information("nasince\n");
#    (  defined($sw_quarantine) || defined(@sw_ignore) ||
#       defined($sw_autopurge) || defined($sw_region)  || defined($sw_autorecover)
#    ) && do {$log->assertion_failed("Wrong syntax\n".$usage);};

#    my @views;
#    $log->assertion_failed("ERROR: Wrong date format (use YYYY-DD-MM)\n") unless vwsstgs_nasince($sw_nasince,\@views);
#    foreach (sort @views) {
#      $log->information($_);
#      defined($sw_autoquarantine) && do {
#        my ($d, $stg) = split(/\t/, $_);
#        if (quarantine_stg($stg)) {
#          $log->information("View was quarantined succesfully\n");
#        } else {
#          $log->error("View was NOT quarantined\n");
#        }
#      };
#    }
#    exit 0;
#  };
#}

#sub quarantine_mode(){
#  defined($sw_quarantine) && do {
#    $log->information("quarantine\n");
#    (  defined(@sw_ignore) || defined($sw_autoquarantine) || defined($sw_autopurge) ||
#       defined($sw_region)  || defined($sw_autorecover)
#    ) && do {$log->assertion_failed("Wrong syntax\n".$usage);};
#    if (quarantine_stg($sw_quarantine)) {
#      $log->information("View \"$sw_quarantine\" was quarantined succesfully\n");
#    } else {
#      $log->error("View \"$sw_quarantine\" was NOT quarantined\n");
#    }
#    exit 0;
#  };
#}

#sub ignore_mode(){
#  defined(@sw_ignore) && do{
#    (  defined(@sw_noignore) || defined($sw_autoquarantine) || defined($sw_autopurge)  || defined($sw_autorecover)) && do {$log->assertion_failed("Wrong syntax\n".$usage);};
#    $log->information("ignore\n");
#    #rw2 cleanup project reimplement ARGV (remember logfile uses it right now)
#    @sw_ignore = split(/;/,join(';',@sw_ignore));
#    foreach (@sw_ignore) {
#        my $viewtag = $_;
#        my $region_switch = (defined($sw_region))? "-region $sw_region":"";
#        $_ =  `cleartool lsview $region_switch $viewtag`;
#        $? && $log->error($?.$_."\nCould not find view $viewtag to ignore\n");
#        /^[\s\*]*(\S*)\s*(\S*)$/; # Any number of whitespaces or * (if the view is started) followed by non-whitespace chars (the view tag) followed by some whitespaces and tne another set of non-whitespace chars (the view storage)
#        print $2; #rw2 debug??
#        my $stg = $2;

#        my $ignore_file_loc = $2."\\admin\\".$view_q_ignore_file;

#        open  VIEW_Q_IGNORE_FILE ,">$ignore_file_loc" or $log->assertion_failed("Couldn't open '$ignore_file_loc'\n");
#        print VIEW_Q_IGNORE_FILE "This view storage is ignored by $Scriptfile\nDelete this file to ";
#        close VIEW_Q_IGNORE_FILE or $log->error("Couldn't close '$ignore_file_loc'\n");
#        $log->information("Viewtag '$viewtag' has been set to ignored\n");
#    } # end foreach
#    exit 0;
#  }; # end ignore

#  defined(@sw_noignore) && do{
#    $log->information("noignore\n");
#    @sw_noignore = split(/;/,join(';',@sw_noignore));
#    foreach (@sw_noignore) {
#        my $viewtag = $_;
#        my $region_switch = (defined($sw_region))? "-region $sw_region":"";
#        $_ =  `cleartool lsview $region_switch $viewtag`;
#        #rw2 error(view not found), not assertion
#        $? && $log->assertion_failed("\n".$usage);

#        # Any number of whitespaces or * (if the view is started) followed by non-whitespace chars
#        # (the view tag) followed by some whitespaces and tne another set of non-whitespace chars (the view storage)
#        /^[\s\*]*(\S*)\s*(\S*)$/;
#        my $stg = $2;

#        my $ignore_file_loc = $2."\\admin\\".$view_q_ignore_file;
#        unlink $ignore_file_loc;
#        $log->information("Viewtag '$viewtag' has been unignored\n");
#    } # end foreach
#    exit 0;
#  }; # end noignore
#}

########################################

#=head3 lsquarantined( )

#NOTE: This function will only run on ClearCase registry servers!!!

#This function lists all the quarantined views.

#The format of the listing is the local view storage (as reported by lsview -age).

#A quarantined view is defined as a view that is reported "stranded" by rgy_check and which has
#a .view_quarantine file in the admin directory of the storage.

#Parameters:

#  none

#Returns:

#  @result    =    The list of quarantined storages.

#=cut

#sub lsquarantined( ){
#  my @result;
#  foreach (grep(/-local_path/, `rgy_check -views 2>&1`)){
#    /-local_path = \"(\S*)?\"/;
#    push(@result, "$1\n") if (-e "$1\\admin\\$view_q_file");
#  };
#  return @result;
#}

#=head3 recover_stg( $stg )

#This function recovers a view storage.

#It will recreate all the tags in all regions where it was tagged at the time it was quarantined.

#Parameters:

#  $stg   = The storage to quarantine (the global one, as reported by a lsview command, or
#           simply the local-path as reported by rgy_check)

#Returns:

#  1    =    Success
#  0    =    The $stg does not contain a .view_quarantine file in the admin directory.

#=cut

#sub recover_stg( $ ){
#  my $stg = shift;
#  chomp($stg);
#  my $view_q_file_loc = "$stg\\admin\\$view_q_file";
#  return 0 unless (-e $view_q_file_loc);
#  open  VIEW_Q_FILE ,"$view_q_file_loc" or die "Couldn't open '$view_q_file_loc'\n";
#  foreach (<VIEW_Q_FILE>){$log->information($_); system($_);$_= ($?)?"ERROR\n":"Success\n"; $log->information($_);};
#  close VIEW_Q_FILE or $log->error("Couldn't close '$view_q_file_loc'\n");

#  # Something is delaying the close above, the file is not ready for deletion
#  # I have to keep trying - I'll give it 40 shots and then I'll bail out
#  # ...Need to improve this bit whne i get the time!
#  $_ = 0; while ($_ < 40 && !unlink $view_q_file_loc){$_++;};

#  return 1;
#}

#=head3 purge_stg( $stg )

#This function purges a view storage.

#It will recreate one intermediate tag to the view stg and then do a regular
#(safe) view removal.

#Parameters:

#  $stg   = The storage to purge (the global one, as reported by a lsview command, or
#           simply the local-path as reported by rgy_check)

#Returns:

#  1    =    Success
#  0    =    The $stg does not contain a .view_quarantine file or the $stg contains
#            a .view_q_ignore file.

#=cut

#sub purge_stg($){
#  my $stg = shift;
#  chomp($stg); # Stg can be local or global so we only use it
#  my $view_q_file_loc = "$stg\\admin\\$view_q_file";
#  (-e $view_q_file_loc)  || do {
#    $log->error("ERROR: '$stg' is not a quarantined storage\n");
#    return 0;
#  };

#  my $ignore_file_loc = $stg."\\admin\\".$view_q_ignore_file;
#  (-e $ignore_file_loc)  && do {
#    $log->error("ERROR: '$stg' ignored for quarantine\n");
#    return 0;
#  };

#  open  VIEW_Q_FILE ,"$view_q_file_loc" or die "Couldn't open '$view_q_file_loc'\n";
#  @_ = <VIEW_Q_FILE>;
#  close VIEW_Q_FILE or $log->error("Couldn't close '$view_q_file_loc'\n");
#  $_ = @_[0]; # Cache the first entry (we really just need the global storage, so any entry will do)
#  /\s(\S*)$/;  # The stg is the last part (whitespace separated) of the stream;

#  my $mktagcmd = "cleartool mktag -view -tag VIEW_Q_TEMP_TAG $1";
#  my $endviewcmd = "cleartool endview -server VIEW_Q_TEMP_TAG";
#  my $rmviewcmd = "cleartool rmview $1";

#  $log->information("$mktagcmd\n");
#  system("$mktagcmd");
#  if ($?) {
#    $log->error("Make tag failed with exitcode: ".($?/256)."\n"); #/ #rw2 EPIC syntax highlight fixer
#  } else {
#    $log->information("Make tag successful\n");
#  }

#  $log->information("$endviewcmd\n");
#  system("$endviewcmd");
#  if ($?) {
#    $log->error("End view failed with exitcode: ".($?/256)."\n"); #/ #rw2 EPIC syntax highlight fixer
#  } else {
#    $log->information("End view successful\n");
#  }

#  $log->information("$rmviewcmd\n");
#  system("$rmviewcmd");
#  if ($?) {
#    $log->error("Remove view failed with exitcode: ".($?/256)."\n"); #/ #rw2 EPIC syntax highlight fixer
#    $log->information("Search for temptag VIEW_Q_TEMP_TAG returns "  . `cleartool lsview -s VIEW_Q_TEMP_TAG` . "\n");
#    if ($?) {
#        $log->information("VIEW_Q_TEMP_TAG was not found, continuing\n");
#    } else {
#        $log->error("VIEW_Q_TEMP_TAG found, removing it now\n");
#        `cleartool rmtag -view VIEW_Q_TEMP_TAG`;
#    }
#  } else {
#    $log->information("Remove view successful\n");
#  }

#  return 1;
#}

#=head3 quarantine_stg( $stg )

#This function quarantines a view storage.

#It will untag tags in all regions and record the reverse commands (the corresponding
#mktag commands) in a file named .view_quarantine located in the admin directory of the
#view storage.

#Parameters:

#  $stg   = The storage to quarantine (the global one, as reported by a lsview command)

#Returns:

#  1    =    Success
#  0    =    The $stg parameter is invalid - nothing to do!

#=cut

#sub quarantine_stg( $ ){
#  my $stg = shift;
#  chomp($stg);
#  prepare_stg_directory();
#  return 0 unless defined($stg_directory{"$stg"}); # Get out if the view storage has no entry in the directory

#  my $ignore_file_loc = $stg."\\admin\\".$view_q_ignore_file;
#  (-e $ignore_file_loc)  && do {
#    $log->error($stg." ignored for quarantine\n");
#    return 0;
#  };
#  # Only permit dynamic views
#  @_ = split(/;/, $stg_directory{"$stg"}); # Turn the semi-colon seprated list of tags into an array
#  $_ = $_[0];                      # Get a region/tag pair (anyone will do, so we just grab the first)
#  s/-tag//;                        # strip the -tag switch, it's not used in lsview

#  if (grep {/^Properties+.*dynamic/} `cleartool lsview -pro -full $_`) {
#    $log->information("View \"$stg\" is a dynamic view\n");
#  } else {
#    $log->error("The view \"$stg\" is a snapshot view.\nSnapshotviews are currently not supported by view_q.pl\n");
#    return 0;
#  }

#  my @rmtags;
#  my @mktags;
#  foreach (split(/;/, $stg_directory{"$stg"})){
#     push(@mktags, "cleartool mktag -view ".$_." ".$stg."\n");
#     s/-tag//;  # strip the -tag switch which isn't used in rmtag
#     push(@rmtags, "cleartool rmtag -view ".$_);
#  }
#  my $view_q_file_loc = $stg."\\admin\\".$view_q_file;
#  open  VIEW_Q_FILE ,">$view_q_file_loc" or $log->assertion_failed("Couldn't open '$view_q_file_loc'\n");
#  foreach (@mktags){print VIEW_Q_FILE $_;};
#  close VIEW_Q_FILE;
#  foreach (@rmtags){$log->information($_."\n");system($_);};
#  return 1;
#}

#=head3 vwsstgs_nasince( $cut_date, \@result )

#This function pushes (global) view storage locations onto the result array
#handed into the sub as a reference if they haven't been accessed since $cut_date.

#The format of the resulting list entries are like this:

#  <YYYY-MM-DD> <view_stg>

#Where  view <YYYY-MM-DD> is the last accessed date, and <view_stg> is the global view storage location.

#Parameters:

#  $cut_date      =  The date to compare against. The scalar must be in the format YYYY-DD-MM
#  \@result       =  An array reference passed into the sub function

#Returns:

#  1    =    The content of @result is trust worthy
#  0    =    The $cut_date is in an unsupported format. The content of @result is crab!

#=cut

#sub vwsstgs_nasince($$){
#  my $cut_date = shift;
#  my $result = shift;
#  return 0 unless ($cut_date =~ /(\d\d\d\d-\d\d-\d\d)/);
#  prepare_stg_directory();
#  foreach my $stg (keys(%stg_directory)){
#    @_ = split(/;/, $stg_directory{"$stg"}); # Turn the semi-colon seprated list of tags into an array
#    $_ = $_[0];                      # Get a region/tag pair (anyone will do, so we just grab the first)
#    s/-tag//;                        # strip the -tag switch, it's not used in lsview
#    @_ = split(/\n/,`cleartool lsview -age $_`);       # lsview with the -age switch return two lines
#    $_ = @_[1];                      # Grab the second line (where the relevant timestamp is listed)
#    /(\d\d\d\d-\d\d-\d\d)/;          # Get the date in the format YYYY-MM-DD

#    push(@$result, $1."\t".$stg."\n") if $1 le $cut_date; #If the last accessed date is prior to the cut_date, push it onto the result.
#  }
#  return 1;
#}

#=head3 sub prepare_stg_directory( )

#This function is related to the global hash: %stg_directory.

#%stg_directory is used be several sub functions as a common directory listing of view storages
#and view tags.

#After it has been prepared, the format of the hash entries are like this:

#  keys                 = The global view storage location;
#  values               = A semi-colon separated list of all region/tags pairs in the
#                         format: -region <region> -tag <tag>

#This function validates that the global hash containing all views across all regions is
#loaded and trustworthy.

#All operations querying the directory should call this sub function first.

#Parameters:

#  none

#Returns:

#  0      The %stg_directory is already prepared, it will be reused.
#  1      The %stg_directory has been prepared.

#=cut

#sub prepare_stg_directory(){
#  return 0 if keys(%stg_directory); # Someone else already prepared the directory, reuse it! Let's get out.
#  foreach my $region (`cleartool lsregion`){
#    chomp($region);
#    foreach (`cleartool lsview -region $region`){
#      /^[\s\*]*(\S*)\s*(\S*)$/; # Any number of whitespaces or * (if the view is started) followed by non-whitespace chars (the view tag) followed by some whitespaces and tne another set of non-whitespace chars (the view storage)
#      $stg_directory{"$2"}=$stg_directory{"$2"}."-region \"$region\" -tag \"$1\";"; #build a unique list of view storages containing the tags in all regions
#    }
#  }
#  return 1
#}
