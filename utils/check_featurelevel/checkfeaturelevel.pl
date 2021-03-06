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
our $VERSION = "0.2";
our $BUILD   = "1";

# Header history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$BUILD
#    
#     Check feature level, raise replica family levels
#     Execute with -help switch to learn more
#
#     Date:       
#     Author:    
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
2014-12-08  Filip Korling  Version 0.1: 1st release
2015-02-03  Olof Aldin     Version 0.2: Added support for cleartool chflevel
                                        and reporting on vob family flevel
-------------------------------------------------------------------------
 
ENDREVISION

my $usage = <<ENDUSAGE;
$Scriptfile -help
Switches -site site [-vob vobtag | -allvobs] -level featurelevel
Auxiliary switches [-[no]debug | -[no]verbose | -[no]logfile [location]
 
ENDUSAGE

my $doc = <<ENDDOC;
 
-help                   Get help with the script syntax etc. (you are watching it now)
-site <site>             Mandatory argument: prefix for the current site, used for determining if mastership is local.
-vob <vobtag>            The vobtag to check, check a single vob. Mandatory unless
                         -allvobs is specified
-allvobs                 Boolean. Check all vobs, then you can not use -vob <vobtag>
-n                       Boolean. DRY RUN. Report what would be done, but don't do any changes.
-level                   Integer. Desired feature level.
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
    $sw_verbose,   $sw_debug, $sw_current_site,$sw_dry_run,
    $sw_desired_fl_level, $sw_expected_schema,
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
&check_feature_level();
#### SWITCH ####
$log->assertion_failed("$header\nWrong syntax! Don't know what you want to do ? \n\n$usage");
###########################################################################################

sub validate_options () {

    %options = (
        "n!"             => \$sw_dry_run, # don't do things, only show
        "site=s"         => \$sw_current_site, # string, current site
        "level=i"        => \$sw_desired_fl_level, # integer, desired feature level
        "schema=i"        => \$sw_expected_schema, # integer, expected schema
        "vob=s"           => \$sw_vob,  # string, a single vobtag
        "allvobs"         => \$sw_allvobs, # bool, check all visible vobs
        "logfile!"       => \$sw_logfile,
        "debug!"         => \$sw_debug,
        "verbose!"       => \$sw_verbose,
    );

    die "$usage" unless GetOptions(%options);
    die "$usage" unless $sw_current_site;
    die "$usage" unless $sw_desired_fl_level;

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

    my %family_fl_raise_hosts;
    my %unrepl_fl_raise_hosts;
    sub check_feature_level () {

    foreach my $vob (@voblist) {
        my $info = "Checking vob $vob";  
        
        # Find vob info: family fl, schema version and vob fl
        my $vob_description = run("cleartool describe -l vob:$vob");
        if ($vob_description !~ /VOB family feature level:\s+(\d).*database schema version:\s+(\d+).*FeatureLevel =\s+(\d+)/s) {
             $log->error("Failed to match any information for $vob")    ;
        }
        
        my ($vob_family_fl, $vob_schema, $replica_fl ) = ($1,$2,$3);
        my $vob_master_replica;
        my $vob_is_mastered_here = 1;
        my $vob_info = " (non-replicated)\n\tFeature Level: $vob_family_fl Schema: $vob_schema";
        
        # if the vob is replicated, it it mastered at a replica
        if ($vob_description =~ /master replica:\s+([\w]+)@/s) {
            $vob_master_replica = $1;
            $vob_is_mastered_here = 0 unless $sw_current_site == substr($vob_master_replica,0,3);

            $vob_info = " (replicated)\n\tVob master: $vob_master_replica ($vob_is_mastered_here) Feature Level: $vob_family_fl Schema: $vob_schema"     
        }

        if ($sw_expected_schema && $sw_expected_schema!=$vob_schema) {
            $log->information($info . $vob_info . " (but expected schema is $sw_expected_schema)");
        } else {
             $info = $info . $vob_info if $sw_verbose;
            $log->information($info) 
        }

        if (! $vob_master_replica) {
            if ($vob_description !~ /FeatureLevel\s+=\s+(\d+)/s) {
                $log->error("Failed to match any information for local $vob");
            }
            
            if($sw_desired_fl_level >  $1) {
                # Need to find out vob server hostname since unreplicated vob feature level
                # can only be changed locally from the vob server host                
                my $vob_desc_output = run("cleartool describe -l vob:$vob");
                $vob_desc_output =~ /.*VOB storage host:pathname "([^:]+):/;
                my $vob_host = $1;
                $unrepl_fl_raise_hosts{$vob_host} = "" unless (defined($unrepl_fl_raise_hosts{$vob_host}));
                $unrepl_fl_raise_hosts{$vob_host} =  $unrepl_fl_raise_hosts{$vob_host} . ":" . $vob;                        
            }

        } else {
            # Get info for all replicas in vob
            my $replicas = run("multitool lsreplica -l -invob $vob");

            my @replica_list = split /replica "(\w+)"/,$replicas;
            shift @replica_list;

                        # number of replicas for this vob
            my $nrof_replicas = 0;
            while (@replica_list) {
                  my ($rep,$rest) = splice @replica_list, 0, 2;
                $nrof_replicas = $nrof_replicas + 1;
              
                  # skip replicas we can't get info for
                  next unless 
                      $rest =~ /master replica:\s(\w{3})(\w+)@([\\\w]+).*feature level:\s+(\w+)/s;
                  
                my $replica_info = "\tReplica: $rep has feature level $4";
                  if ($1 eq $sw_current_site) {
                      
                      # replica mastered at this site, report it            
                      if($4 eq "unknown" || $sw_desired_fl_level > $4) {

                          $log->information($replica_info . " (should be raised to $sw_desired_fl_level)");
                        my $cmd = "cleartool chflevel -replica $sw_desired_fl_level replica:${rep}\@${vob}";
                        if ($sw_dry_run) {
                            $log->information("Dry run (just print): $cmd");
                        } else {
                            my $chflevel_output;
                                                $chflevel_output = run($cmd);
                            if ($chflevel_output =~ /.*Replica feature level raised to.*/ ) {
                                $log->information("Replica feature level was successfully raised to $sw_desired_fl_level for replica:${rep}\@${vob}\n");
                                $nrof_replicas = $nrof_replicas - 1;
                            } else {
                                $log->error("Raising feature level for replica:${rep}\@${vob} failed with message:\n" . $chflevel_output . "\n");
                            }
                        }
                      } else {
                          $log->information($replica_info) if $sw_verbose;
                          # decrease number of replicas with FL less than desired level
                          $nrof_replicas = $nrof_replicas - 1;
                      }
                  } else {
                      $log->information($replica_info . " (remote)") if $sw_verbose; 
                    if ($sw_desired_fl_level <= $4) {
                          # decrease number of replicas with FL less than desired level
                          $nrof_replicas = $nrof_replicas - 1;
                    }
                  }
            }

            # if all replicas have the right fl, then check if vob family feature level could be raised
            if (($nrof_replicas == 0) && 
                $vob_is_mastered_here &&
                ($sw_desired_fl_level > $vob_family_fl))  {

                                # Need to find out vob server hostname since vob family feature level
                                # can only be changed locally from the vob server host                
                my $vob_desc_output = run("cleartool describe -l vob:$vob");
                $vob_desc_output =~ /.*VOB storage host:pathname "([^:]+):/;
                my $vob_host = $1;
                $family_fl_raise_hosts{$vob_host} = "" unless (defined($family_fl_raise_hosts{$vob_host}));
                $family_fl_raise_hosts{$vob_host} =  $family_fl_raise_hosts{$vob_host} . ":" . $vob;
            }
        }
    }
    $log->information("");
    foreach my $vob_host (keys %family_fl_raise_hosts) {
        $log->information("HOST $vob_host needs to raise vob family feature levels (run locally on vob server):");
        my @sp = split(":",$family_fl_raise_hosts{$vob_host});
        foreach my $vob (@sp) {
            next unless ($vob);

            # This site can only upgrade family feature levels for vobs mastered here. Therefore
            # ignore vobs not mastered here
            my $vobmastershipreplica = `cleartool describe -fmt %[master]p vob:$vob`;
            my @sp = split("_",$vobmastershipreplica);
            my $mastersite = $sp[0];
            if ($mastersite ne $sw_current_site) {
                $log->information("Vob $vob needs to raise family feature level and is ready for it but is mastered in $mastersite. Ignoring.\n");
                next;
            }

            # to get return codes from script right
            if ($sw_dry_run) {
                $log->information("cleartool chflevel -force -family $sw_desired_fl_level vob:$vob");
            } else {
                $log->error("cleartool chflevel -force -family $sw_desired_fl_level vob:$vob");
            }
        }
    }

    $log->information("");
    foreach my $vob_host (keys %unrepl_fl_raise_hosts) {
        $log->information("HOST $vob_host needs to raise vob (unrepl) feature levels (run locally on vob server):");
        if ($sw_dry_run) {
            $log->information("cleartool chflevel -auto $sw_desired_fl_level");
        } else {
            $log->error("cleartool chflevel -auto $sw_desired_fl_level");
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
