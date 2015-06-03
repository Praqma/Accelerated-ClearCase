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

&help_mode();
&getvobs();
exit main();

###########################################################################################

sub validate_options () {

    %options = (
        "dryrun!"        => \$sw_dry_run, # don't do things, only show
        "view=s"         => \$sw_view_name, # string, temp view to run in
        "view_stgloc=s"  => \$sw_view_stgloc, # stgloc to create view on
        "vob=s"          => \$sw_vob,  # string, a single vobtag
        "allvobs"        => \$sw_allvobs, # bool, check all visible vobs
    );

    die "\nUsage: $usage" unless GetOptions(%options);
    die "\nUsage: $usage" unless $sw_view_name;
    die "\nUsage: $usage" unless $sw_view_stgloc;
    die "\nUsage: $usage" unless ($sw_vob || $sw_allvobs);

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

##### MAIN #####

sub main () {
    run("cleartool mount -all");

    # Verify existence or create temporary view
    my @lsview = run("cleartool lsview -s $sw_view_name",1);
    my $lsview = join(" ",@lsview);

    if ( $lsview =~ /Error: No matching entries found/ ) {
        run("cleartool mkview -tag $sw_view_name -stgloc $sw_view_stgloc");
        @lsview = run("cleartool lsview $sw_view_name",1);
        $lsview = join(" ",@lsview);
        die "Unable to create working view ($sw_view_name). Exiting without doing anything" if ( $lsview =~ /Error: No matching entries found/);
    }

    run("cleartool startview $sw_view_name",1);

    my $perms;
    my $cmd;
    my $error = 0;
    my $desc;

    foreach my $vob (@voblist) {
        my $info = "Checking vob $vob";  

	#$cmd = "cleartool mount " . $vob;
	#run($cmd);

        $cmd = "cleartool describe m:\\${sw_view_name}" . ${vob} . "\\.";
	$desc = join(" ",run($cmd,1));
	$desc =~ s/\n/ /g;
	$desc =~ /^.*Element Protection:.*Other:\s+: ([rwx-][rwx-][rwx-]).*$/;
	$perms = $1;
	die "Unable to find permissions of vob root element for $vob" unless ($perms);

        # Make sure permissions are correct
        $cmd = "cleartool protect -chmod 770 m:\\${sw_view_name}" . ${vob} . "\\.";
        if ( $perms ne "---" && ! $sw_dry_run ) {
        	run($cmd);
        	print "UPDATE: Running: $cmd\n";

        	$cmd = "cleartool describe m:\\${sw_view_name}" . ${vob} . "\\.";
		$desc = join(" ",run($cmd,1));
		$desc =~ s/\n/ /g;
		$desc =~ /^.*Element Protection:.*Other:\s+: ([rwx-][rwx-][rwx-]).*$/;
		$perms = $1;
		if ( !$perms ) {
		        $error = $error + 1;
			print "ERROR: Unable to find permissions of vob root element for " . $vob;
		}
		if ( $perms ne "---" ) {
			$error = $error + 1;
			print "ERROR: Unable to update permissions of vob root element for " . $vob;
		}

        } else {
          if ( $perms ne "---" && $sw_dry_run ) {
            print "DRY RUN: Would have run: $cmd\n";
          } else {
            print "INFO: OK permissions for $vob\n";
          }
        }
    }
    if ( $error > 0 ) {
        print "\nERROR: There were $error errors found\n";
    }

    return $error;
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
        print "ERROR: The command: $cmd failed!.\nIt returned:\n$retval_scl\n";
    };
    return @retval_list if $aslist;
    return $retval_scl;
}

