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
#     Execute with -help switch to learn more
#
#     Date:       
#     Author:    
#     Copyright: 
#     License:    
#     Support:    http://www.praqma.info
#########################################################################
 
ENDHEADER
# Revision information
################################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2014-12-08  Filip Korling  Version 0.1: 1st release
-------------------------------------------------------------------------
 
ENDREVISION

my $usage = <<ENDUSAGE;
$Scriptfile -help
Switches -site site [-vob vobtag | -allvobs] 
Auxiliary switches [-[no]debug | -[no]verbose | -[no]logfile [location]
 
ENDUSAGE

my $doc = <<ENDDOC;
 
-help                   Get help with the script syntax etc. (you are watching it now)
-site <site>     Mandatory argument: prefix for the current site, used for determining if mastership is local.
-vob <vobtag>    The vobtag to check, check a single vob. Mandatory unless
                 -allvobs is specified
-allvobs         Boolean. Check all vobs, then you can not use -vob <vobtag>
-n               DRY RUN. Explain what would happen but don't do it.
--- Auxiliary switches (can be omitted or used on all functions)---
 
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
	$sw_help,  $sw_logfile, $sw_vob, $sw_allvobs, $sw_vob,
	$sw_verbose,   $sw_debug, $sw_current_site, $sw_dry_run,
	@voblist, %options,   
);

# TEST TEST TEST
#my $gin_testvob ="\\bbSensorActHdl_Stub";
#my $gma_testvob = "\\rwComponentConfigurator_Dev";
# TEST TEST TEST

&validate_options();

#### SWITCH ####
&help_mode();
&enable_log();
&getvobs();
&chreplicas();
#### SWITCH ####
$log->assertion_failed("$header\nWrong syntax! Don't know what you want to do ? \n\n$usage");
###########################################################################################

sub validate_options () {

	%options = (
		"n!"			 => \$sw_dry_run, # don't do things, only show
		"site=s"         => \$sw_current_site, # string, current site
		"vob=s"  		 => \$sw_vob,  # string, a single vobtag
        "allvobs"		 => \$sw_allvobs, # bool, check all visible vobs
		"logfile!"       => \$sw_logfile,
		"debug!"         => \$sw_debug,
		"verbose!"       => \$sw_verbose,
	);

	die "$usage" unless GetOptions(%options);
	die "$usage" unless $sw_current_site;

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
        @voblist = sort(run('cleartool lsvob -s',1));
        chomp(@voblist);
    }
}

#  for each <replica<> in <replicas> in <vob> in <VOBS>
#    if the <replica> is mastered by <this> site 
#    and replica belongs to <another> site 
#      transfer mastership to <another> site
sub chreplicas () {
	$log->information("DRY RUN -- only showing what would happen") if $sw_dry_run;		

	foreach my $vob (@voblist) {
		$sw_verbose && $log->information("Checking replicas in vob $vob");  
		foreach (run("cleartool lsreplica -fmt \"%n %[master]p\\n\" -invob $vob",1)) {
			
			/(.*) (.*)@(.*)/;  
			#print "Replica: >$1<  Master: >$2<\n"; 
			
			my $mastering_site = substr $2,0,3;

			# if replica not mastered here, ignore it
			if ($mastering_site eq $sw_current_site) {

				# change master to its own site if currently mastered by this site 
				if ( $1 ne $2) {
					my $replica =  $1.'@'.$vob;
					
					if ($sw_dry_run) {
						
						$sw_verbose && $log->information("DRYRUN: would have chmaster -nc $replica replica:$replica");
					} else {
						$log->information("Executing: multitool chmaster -nc $replica replica:$replica");
						run("multitool chmaster -nc $replica replica:$replica");
					}

					
				} else {
					# mastered at this site, check if req for mastership is enabled
					my $rfq_status = run("cleartool describe -fmt \"%[reqmaster]p\" replica:$1\@$vob",0);
					if ($rfq_status eq "disabled")  {
						if ($sw_dry_run) {	
							$sw_verbose && $log->information("DRYRUN: would have reqmaster \-enable vob:$vob");
						} else {
							$log->information("Executing: multitool reqmaster \–enable vob:$vob");
							run("multitool reqmaster -enable vob:$vob");
						}
					} else {
						$sw_verbose && $log->information("Already enabled for rfq: $1\@$vob");
					}
				}	
			}	
		}
	}	
	exit $log->get_accumulated_errorlevel();
}

sub run ($$) {

    # Generic sub for calling system and monitor return value

    my $cmd         = shift;
    my $aslist      = shift;
#    my $expecterror = shift; # optional
    my $cmdex       = $cmd . ' 2>&1';
    my @retval_list = qx($cmdex);


    my $retval_scl  = join '', @retval_list;

#    if ($expecterror)

    $? && do {
        $log->enable(1);
        $log->error("The command: $cmd failed!.\nIt returned:\n$retval_scl\n");
    };
    return @retval_list if $aslist;
    return $retval_scl;
}
