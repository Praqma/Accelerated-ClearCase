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
#     Runs chepoch -actual for all sibling replicas for all vobs
#     Execute with -help switch to learn more
#
#     Date:       2015-07-27
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
2015-07-27  Olof Aldin     Initial version
-------------------------------------------------------------------------
 
ENDREVISION

my $usage = <<ENDUSAGE;
$Scriptfile -help
Switches -site site [-vob vobtag | -allvobs]
Auxiliary switches [-[no]debug | -[no]verbose | -[no]logfile [location] -ignorePrefix prefix1[,prefix2]+
 
ENDUSAGE

my $doc = <<ENDDOC;
 
-help                   Get help with the script syntax etc. (you are watching it now)
-vob <vobtag>            The vobtag to check, check a single vob. Mandatory unless
                         -allvobs is specified
-allvobs                 Boolean. Check all vobs, then you can not use -vob <vobtag>
-n                       Boolean. DRY RUN. Report what would be done, but don't do any changes.
--- Auxiliary switches (can be omitted or used on all functions)---
 
-ignorePrefix prefix    List replica prefixes that shall be ignored/not run checpoch actual
-[no]logfile [location] Sets whether or not to create a logfile.
                        May define the name [and location] of the logfile.
                        Default value is the temp dir (usually under
                        users " doc &set ") and " view_q . pl [PID] . log "
 
-[no]verbose            Toggles verbose mode (log to STDOUT)
                        Default is on (for manual execution, verbose is recommended)
 
-[no]debug              Toggles debug mode (additional information + force logfile + verbose)
                        Default is off
 
ENDDOC

# Log and monitor default settings (overwriteable at execution)
my $debug        = 0;                           # Set 1 for testing purpose
my $verbose_mode = 1;
my $log_enabled  = 1;

### Global variables ###

our $log                = scriptlog->new;
our (
     $sw_help,  $sw_logfile, $sw_vob, $sw_allvobs,
    $sw_verbose,   $sw_debug, $sw_ignorePrefixes ,$sw_dry_run,
    @voblist, %options,   
);

&validate_options();

#### SWITCH ####
&help_mode();
&enable_log();
&getvobs();
&chepoch_actual();
#### SWITCH ####
$log->assertion_failed("$header\nWrong syntax! Don't know what you want to do ? \n\n$usage");
###########################################################################################

sub validate_options () {

    %options = (
        "n!"             => \$sw_dry_run,          # don't do things, only show
        "ignorePrefix=s" => \$sw_ignorePrefixes,   # integer, expected schema
        "vob=s"          => \$sw_vob,              # string, a single vobtag
        "allvobs"        => \$sw_allvobs,          # bool, check all visible vobs
        "logfile!"       => \$sw_logfile,
        "debug!"         => \$sw_debug,
        "verbose!"       => \$sw_verbose,
    );

    die "$usage" unless GetOptions(%options);
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

#### MAIN ####

    sub chepoch_actual () {

    my @ignorePrefixes = split(",",$sw_ignorePrefixes);
    my $cmd;
	my $out;
	my $message;

    foreach my $vob (@voblist) {
	
		# first check if multisite is enabled
		my $lsreplica = run("multitool lsreplica -short -invob $vob");
		my $nbr_of_lines = $lsreplica =~ tr/\n//;
		print "DEBUG: Vob $vob is not replicated. Ignoring...\n" if ($sw_debug && ($nbr_of_lines <= 1));
		next if ($nbr_of_lines <= 1);
		print "Vob $vob has $nbr_of_lines replicas.\n" if ($sw_debug);

        my $message = "Checking vob $vob";  
		print "INFO: " . $message . "\n" if ($sw_verbose || $sw_debug);
		
		# then run again to get siblings
        $lsreplica = run("multitool lsreplica -short -siblings -invob $vob");
        my @lsreplicas = split("\n",$lsreplica);

        foreach my $replica (@lsreplicas) {
            $replica =~ /^([^_]+)_(.*)$/;
            my $prefix = $1;
            my $vobName = $2;
            die "Unable to extract site prefix from vob ($vob). Prefix: $prefix" unless ($prefix);
            die "Unable to extract vob name from vob ($vob). Vob name: $vobName" unless ($vobName);

			
			if ( grep { $prefix eq $_ } @ignorePrefixes ) {
		        $message = "DEBUG: Ignoring replica $replica due to prefix in ignore prefix (prefix: $prefix)";
			    print $message . "\n" if ($sw_debug);
                next;
            }

            $cmd = "multitool chepoch -actual replica:$replica\@$vob";
            print "INFO: cmd: $cmd ::\n" if ($sw_debug || $sw_verbose);
            $out = run($cmd);
			print "$out" if ($sw_debug);
        }
    }

	print "DEBUG: accumulated error level: " . $log->get_accumulated_errorlevel() . "::\n";
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

