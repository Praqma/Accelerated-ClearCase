require 5.001;
use strict;


# Getting the script dir
our ( $Scriptdir, $Scriptfile );

BEGIN {
    if ( $0 =~ /(.*[\/\\])(.*)$/ ) {
        $Scriptdir  = $1;
        $Scriptfile = $2;
    }
    else {
        $Scriptdir  = "";
        $Scriptfile = $0;
    }
}

# Use clauses
use lib "$Scriptdir..\\..";
use Getopt::Long;
use praqma::scriptlog;

# File version
our $VERSION = "0.1";
our $BUILD   = "1";

# Header history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$BUILD
#    
#     Checks all vobs in current region and ensures permission
#     on vob root directory is 770. Will set it to 770 if it's not
#
#     Execute with -help switch to learn more
#
#     Date:       2015-06-03
#     Author:     Olof Aldin
#     Copyright: 
#     License:    
#     Support:    http://www.praqma.info/
#########################################################################
 
ENDHEADER
# Revision information
################################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2015-06-03  Olof Aldin     Version 0.1: 1st release
-------------------------------------------------------------------------
 
ENDREVISION

my $usage = <<ENDUSAGE;
$Scriptfile -help
Switches [-vob vobtag | -allvobs] -view view_name -view_stgloc stgloc
Auxiliary switches [-dryrun]
 
ENDUSAGE

my $doc = <<ENDDOC;
 
-help                   Get help with the script syntax etc. (you are watching it now)
-vob <vobtag>           The vobtag to check, check a single vob. Mandatory unless
                        -allvobs is specified
-view <view_name>       Temporary view name that will be used. Config spec will be reset
-view_stgloc <stgloc>   Storage location for views that will be used to create the temp view
-allvobs                Boolean. Check all vobs, then you can not use -vob <vobtag>

--- Auxiliary switches (can be omitted or used on all functions)---
 
-dryrun                 Boolean. DRY RUN. Report what would be done, but don't do any changes.
 
ENDDOC

# Log and monitor default settings (overwriteable at execution)
my $debug        = 0;                           # Set 1 for testing purpose
my $verbose_mode = 1;
my $log_enabled  = 1;

### Global variables ###

our $log                = scriptlog->new;
our (
     $sw_help,  $sw_logfile, $sw_vob, $sw_allvobs,
    $sw_verbose,   $sw_debug, $sw_view_name, $sw_dry_run,
    $sw_view_stgloc,
    @voblist, %options,   
);

&validate_options();

#### SWITCH ####
&help_mode();
&enable_log();
&getvobs();
&main();
#### SWITCH ####
$log->assertion_failed("$header\nWrong syntax! Don't know what you want to do ? \n\n$usage");
###########################################################################################

sub validate_options () {

    %options = (
        "dryrun!"        => \$sw_dry_run, # don't do things, only show
        "view=s"         => \$sw_view_name, # string, temp view to run in
        "view_stgloc=s"  => \$sw_view_stgloc, # stgloc to create view on
        "vob=s"          => \$sw_vob,  # string, a single vobtag
        "allvobs"        => \$sw_allvobs, # bool, check all visible vobs
        "logfile!"       => \$sw_logfile,
    );

    die "$usage" unless GetOptions(%options);
    die "$usage" unless $sw_view_name;
    die "$usage" unless $sw_view_stgloc;
    die "$usage" unless ($sw_vob || $sw_allvobs);

}

sub enable_log () {

    # Overwrites the default logging setting, if set manually
    defined($sw_debug) && do { $debug = $sw_debug }
      && ( $verbose_mode = 1 );
    defined($sw_verbose) && do { $verbose_mode = $sw_verbose };
    defined($sw_logfile) && do { $log_enabled  = $sw_logfile };

    my $argv_values = join( ' ', @ARGV );
    foreach (@ARGV) {
        $argv_values = $argv_values . "\"" . $_ . "\" ";    #rw2 use join

    }

    # Ensure consistent time formatting, see IBM Tech note 1249021
    $ENV{'CCASE_ISO_DATE_FMT'} = "1";

    # Checks ARGV for consistency and enables the log
    if ($log_enabled) {
        if ( scalar(@ARGV) gt 1 ) {
            $log->assertion_failed(
                "You have more then one value with no defined reference,\nonly valid option is logfile location \nRecorded values are:$argv_values");
        }
        $log->set_logfile( $ARGV[0] );
        $log->enable();
    }
    else {
        if ( scalar(@ARGV) gt 0 ) {
            $log->assertion_failed("You have value(s) with no defined reference,\nRecorded values are: $argv_values");
        }    # end if scalar(argv)
        $log->conditional_enable();
    }    # end if logfile

    # Sets verbose
    $verbose_mode
      && do {
        $log->set_verbose(1);
      };

    # Sets debug
    $debug
      && do {
        $log->enable();
        $log->set_verbose(1);
        $log->information("DEBUG is ON");
      };

}

sub help_mode () {
    defined($sw_help) && do {
        print $header. $revision . $usage . $doc;
        exit 0;
    };
}

sub getvobs () {
  if ($sw_vob) {
        push @voblist, $sw_vob;
    } else {
        @voblist = sort(run('cleartool lsvob -s ',1));
        chomp(@voblist);
    }
}

# Verify existence or create temporary view
my @lsview = run('cleartool lview $sw_view_name',1);
run ('cleartool mkview -tag $sw_view_name -stgloc $sw_view_stgloc) unless (@lsview);
@lsview = run('cleartool lview $sw_view_name',1);
die "Unable to create working view ($sw_view_name). Exiting without doing anything" unless (@lsview);
run('cleartool startview $sw_view_name',1);

# $log->error("cleartool chflevel -auto $sw_desired_fl_level");

#### MAIN ####

sub main () {
    my $perms;
    #my $group;
    my $cmd;

    foreach my $vob (@voblist) {
        my $info = "Checking vob $vob";  

        # call this as a sub!
        # cleartool describe m:\${sw_view_name}\${vob}\.
        $perms = "rwx";
        #$group = "EMEA\DK-U-CC-Users";

        # Make sure permissions are correct
        $cmd = "cleartool protect -chmod 770 m:\${sw_view_name}\${vob}\.";
        print "DEBUG: $cmd ::\n";
        if ( $perms != "---" && ! $sw_dry_run ) {
          #run($cmd);
          log->information("UPDATE: Running: $cmd ::\n");
          # TBD: Check again or fail
        } else {
          if  $perms != "---" && $sw_dry_run ) {
            log->information("DRY RUN: Would have run: $cmd ::\n");
          } else {
            log->information("INFO: OK permissions for $sw_vob ::\n");
          }
        }
    }
    exit $log->get_accumulated_errorlevel();
}

### END OF MAIN ###

sub run ($$) {

    # Generic sub for calling system and monitor return value

    my $cmd         = shift;
    my $aslist      = shift;
    my $cmdex       = $cmd . ' 2>&1';
    my @retval_list = qx($cmdex);


    my $retval_scl  = join '', @retval_list;

    $? && do {
        $log->enable(1);
        $log->error("The command: $cmd failed!.\nIt returned:\n$retval_scl\n");
    };
    return @retval_list if $aslist;
    return $retval_scl;
}

