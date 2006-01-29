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
		$Scriptdir  = ".";
		$Scriptfile = $0;
	}
}

use lib "$Scriptdir\\..\\..";
use Getopt::Long;
use praqma::scriptlog;
$| = 1;    # autoflush on

#use warnings;

# File version
our $VERSION = "1.0";

# BUILD is revision number!
our $BUILD = "175";

=head1 NAME

Accelerated ClearCase Backup

=head1 SYNOPSIS

Backup utility script for ClearCase

=head1 Description

Used for Automating Backing up ClearCase environment

=head1 AVAILABILITY

To get newest version of this script visit:
http://launchpad.net/acc

=head1 Parameters

Please call the script with -usage command line switch


=head1 Returns

Returns 0 for successfull completion
Returns 1 (or higher) for errors

=cut

my $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$BUILD                             #
#     This script is a Backup Script for ClearCase.                     #
#     In runs in different modes - execute the script with -help        #
#     to learn more.                                                    #
#     It enables e-mail notification using the blat utility             #
#     which is installed seperately. Blat must be configured to work    #
#     properly.                                                         #
#                                                                       #
#     Execute with -help switch to learn more                           #
#                                                                       #
#     Date:       2009-08-25                                            #
#     Author:     Jens Brejner, jens.brejner\@praqma.net                #
#     Copyright:  Praqma A/S, Denmark                                   #
#     License:    GNU General Pulic License                             #
#     Support:    http://launchpad.net/acc                              #
#########################################################################

ENDHEADER

# Revision information
#########################################################################
my $revision = <<ENDREVISION;
$Scriptfile Version $VERSION\.$BUILD
DATE         EDITOR         NOTE
-----------  -------------  ----------------------------------------------
2008-10-23   Lars Kruse     Made the script use BLAT.EXE instead of
                            IBM's NOTIFY.EXE:
                            http://sourceforge.net/projects/blat
                            Using version 2.6.2.0 of BLAT for the
                            validation.
2009-08-25   Jens Brejner   Bumped revision. Script now respects the current
                            lock on a vob. Vobs that are lock -nuser are changed
                            to lock for all users during backup, the lock is restored
                            after backup. Lock comments are respected too, but
                            because of a CC bug, multi-line lock-comments will be
                            flattened to a single line.
                            No changes to the interfaces, but the script now uses
                            Switch.pm, which is part of Ratlperl distribution, just
                            like Getopt
2009-08-29   Jens Brejner   Removing usage of switch.pm. Replace scriptlogccbackup
                            with scriptlog.pm. Publishing this version on launchpad
                            in the acc project.

-------------------------------------------------------------------------

ENDREVISION

# Usage synopsis
#########################################################################
my $usage = <<ENDUSAGE;
The syntax of this command is:
 $Scriptfile  -target vdir
            -vobs {vob_tag[,...] | -all
            [-[no]depend]
            [-livesync [-[no]database]]
            [-[no]triggers]
            [-winrgy {clearcase | key[,...]}
            -directory {vpname[,...]}
            [-verbose] [-logdir log_directory]
            [-notify email[,...] -level {I|W|E}]

 $Scriptfile  -help | -version | -usage

ENDUSAGE

# Help Message
#########################################################################
my $helpmsg = <<ENDHELP;
=========================================================================
"$Scriptfile" Provides utilities for ClearCase backup.

The script returns 0 if ALL operations are succesful - otherwise
it returns 1

NOTE:
This version of the script is only tested on WIN XP platform and
only on ClearCase LT.

$usage
Command line options:

-target vdir                vdir is a directory template that can contain
                            expandable keywords that will be instantiated.
                            The instantiated vdir is the target directory
                            to copy to.
                            The directory will be create the directory if
                            it does not exist.

expandable keywords         The -target vdir and the -directory vpname can both
                            contain expandable keywords. Keywords are capitalized
                            pre-defined tags (embraced by lesser-than / greater than
                            characters like XML or HTML tags. The keywords will be
                            expanded and instantiated as described below:
                            KEYWORD         EXPANDS TO
                            =============   =========================================
                            DDD[+|-min]     a lower-case three-letter abbreviation of
                                            the name of the weekday (mon|tur|wed|thu|
                                            fri|sat|sun). Evaluated from the time of
                                            script execution plus/minus the number of
                                            minutes indicated as an option.
                            =============   =========================================
                            Examples executed on Tuesday 19 August 2008 at 15:00:
                            Now:
                            \\\\server\\share\\backup\\<DDD>
                               expands to:
                            \\\\server\\share\\backup\\tue

                            in 8 hours:
                            \\\\server\\share\\backup\\<DDD+480> expands to:
                               expands to:
                            \\\\server\\share\\backup\\wed

                            16 hours ago:
                            \\\\server\\share\\backup\\<DDD-960> expands to:
                               expands to:
                            \\\\server\\share\\backup\\mon

-vobs {vob_tag[,...] | -all}
                            The VOBs to backup can be specified using one of
                            two identification methods: either using the -all
                            switch which will include all VOBs on the server
                            executing the script or using a comma separated list
                            of VOBs.

-[no]depend                 Specifies if backup should be organized into
                            AdminVOB/client VOB dependencies. If an AdminVOB
                            is included, the sequence of VOB backups is organized
                            so that AdminVOBs are backed up last - after the
                            clients VOBs. -nodepend means that dependencies are not
                            examined and VOBs are backed up in the order they are
                            listed or presented by the ClearCase registry.
                            Default value is -depend.

[-livesync [-[no]database]] Livesync indicates that storage should be copied
                            without locking the VOBs. Open files will be ignored.
                            -[no]database is only relevant with -livesync and
                            Indicates whether or not the database files (.db directory)
                            will be included or not. Default is -nodatabase.

-[no]triggers               Indicates whether triggers (and trigger scripts)
                            will be backed up too. Default is -triggers.

-winrgy clearcase | key[,...]
                            Back up windows registry. Either specify a
                            comma seperated list of keys to back up or
                            simply type the keyword "clearcase" to backup all
                            ClearCase relevant keys.
                            If you specify a named key, it will be backed up
                            recursively, everything below the key is included.
                            If you specify a named key, you shouldn't also use
                            the keyword 'clearcase'. When you specify a key,
                            the clearcase settings are implicitly included, so
                            in this sense a 'key' is actually an 'additional key'.

-directory pname,[...]      Back up a directory. Specify a comma separated list
                            of fully qualified paths to copy. If the specified
                            dir(s) ends with wild-card "\*" (backslash-asterisk)
                            they are backed up recursively. Otherwise they are
                            only backed up one level deep.
                            In Directory Backup Mode, only one directory is
                            allowed.
                            As in the -target switch it's also allowed to specify
                            expandable keywords in the -directory switch which
                            means that they will be expanded and instantiated
                            before the directory is accessed.
                            See further details of what expandable keywords are
                            allowed at the description of the -target switch.

-verbose                    Prints status information as the script processes.
                            if this switch is omitted the script is silent
                            unless an error occurs.

-logdir log_directory       Use this setting explicitly override the
                            directory where logs will be written to. By default,
                            If omitted, the logs will be placed in the root
                            of the final target (target_root+expanded template).
                            The log will be named accbackup.PIDX.log ehere X is
                            the process ID of the script execution.

-notify email[,...] -level I|W|E
                            A comma separated list of email addresses to
                            notify. Ignored if notify.exe (part of ClearCase
                            installation) is not configured correct.
                            The level refers the notification level to subscribe to.
                             I       = Information (includes W+E)
                             W       = Warning (includes E)
                             E       = Error


[-notify email[,...]]       A comma separated list of email addresses to
                            notify. Ignored if notify.exe (part of ClearCase
                            installation) is not configured correct.

[-level I|W|E]              Specifies the notification level to subscribe to
                            email notifications to. Invalid if -notify is
                            omitted.
                             I       = Information (includes W+E)
                             W       = Warning (includes E)
                             E       = Error

-help                       Displays this help message.
-version                    Displays version info and revsion history.
-usage                      Displays the synopsis of the syntax of
                            $Scriptfile
=========================================================================
ENDHELP

use constant WEEKDAYS => qw(
  sun mon tue wed thu fri sat
);

# Declare global switch variables
our (
	$sw_database, $sw_debug,  $sw_depend,   $sw_directory, $sw_help,    $sw_level, $sw_livesync, $sw_logdir, $sw_notify,
	$sw_robocopy, $sw_target, $sw_triggers, $sw_usage,     $sw_verbose, $sw_vobs,  $sw_winrgy,   $sw_version
);

# Declare remaining global variables
our (
	$date,        $destination, $flag_lt, $g_debug,         $g_file,   $g_retval,   @g_notify,
	$g_infolevel, $host,        $log,     $robocopy_params, $template, %masterlist, %options,
	@basevobs,    @processed,   @ucmvobs, @voblist,         %ucmfamily
);

# Define option set, Note 2 switches that are only documented here:
my $undocumented = <<ENDUNDOCUMENTED;

 -robocopy {parameters}      The parameters that RoboCopy should use. you should
                             ONLY change these settings if you have read and
                             understood the reference manual to robocopy.exe.
                             Using this switch overwrites the default.
                             Robocopy.exe is part of Windows 2003 resource kit,
                             which is a free download.

 -debug                      Enable debugging. Will more or less spam STDOUT
                             with variable contents during execution.


ENDUNDOCUMENTED

%options = (
	"robocopy=s"  => \$sw_robocopy,    # UNDOCUMENTED: Overwrite robocopy parameters - you are on your own
	"debug"       => \$sw_debug,       # UNDOCUMENTED: Dump (as in SPAM!) maximal information to STDOUT
	"database!"   => \$sw_database,
	"depend!"     => \$sw_depend,
	"directory=s" => \$sw_directory,
	"help|?"      => \$sw_help,
	"level=s"     => \$sw_level,
	"livesync"    => \$sw_livesync,
	"logdir=s"    => \$sw_logdir,
	"notify=s"    => \$sw_notify,
	"target=s"    => \$sw_target,
	"triggers!"   => \$sw_triggers,
	"usage"       => \$sw_usage,
	"version"     => \$sw_version,
	"verbose"     => \$sw_verbose,
	"vobs=s"      => \$sw_vobs,
	"winrgy=s"    => \$sw_winrgy
);

# Parse options
my $optres = GetOptions(%options);

# Check if the script is executed with -help |-usage |-version
&want_help();

# Check if debug mode should be enabled for the script
&enable_debug();

# Create log object
$log = scriptlog->new();

# enable verbose logging if specified in options
$log->set_verbose($sw_verbose);

# Get current date from scriptlogccbackup method
$date = $log->datestamp();

# Prepare remaining environment, including option usage validation
&initialize();

###################### MAIN LOOP #######################
&debug_print("Entering the main loop\n");

## DO THE VOBS

if ( defined($sw_vobs) ) {
	&debug_print("Doing the VOBs....\n");

	#IF LIVESYNC - WITH OR WITHOUT DATABASE
	( $sw_livesync && ( $sw_database eq 0 ) ) && do {
		&debug_print("\$sw_database has value [$sw_database]\n");

		$log->information("Switch -nodatabase enabled, adding /XD db to robocopy parameters\n");
		$robocopy_params = $robocopy_params . " /XD db ";
	};

	$log->information("\n");    # Just a spacer
	foreach (@voblist) {
		my $nuserswitch = "";    # used to cache -nuser contents
		my $usercomment = "";    # Possible original lock comment
		$log->information("####### Backing up vob:$_ #######\n");

		#LOCK UNLESS LIVESYNC
		if ($sw_livesync) {
			$log->information("\tLivesync mode, not locking vob:$_\n");
		}
		else {
			&do_the_lock( $_, "lock", \$nuserswitch, \$usercomment );
		}

		#COPY STORAGE
		&copy_vob_stg($_);

		#UNLOCK UNLESS LIVESYNC
		&do_the_lock( $_, "unlock", \$nuserswitch, \$usercomment ) unless ($sw_livesync);

		# Process triggers if
		&do_triggers($_) if ($sw_triggers);
		$log->information("\n");    # Just a spacer
	}
}

#if specified we will backup sepecified registry keys..
if ( defined($sw_winrgy) ) {
	&debug_print("Backing up windows Registry");
	$log->information("######## Backing up Windows Registry ########\n");
	&export_winrgy();
	$log->information("\n");        # Just a spacer
}

# if wanted we will backup the specified dir's.
if ( defined($sw_directory) ) {

	&debug_print("Backing up external dir's");
	$log->information("######## Backing up External Dir's ########\n");
	&do_directories;
	$log->information("\n");        # Just a spacer

}

# Get overall error count
$g_retval = $g_retval + ( $log->get_accumulated_errorlevel() );
&notify();

# Update g_retval, if we had trouble in sub notify
$g_retval = $g_retval + ( $log->get_accumulated_errorlevel() );

#End the main loop, close the logfile, return accumulated errorlevel.
$log->DESTROY();
print STDERR "$Scriptfile return value   was $g_retval\n";

exit $g_retval;

#################################  SUBS  #######################################

=head1 FUNCTIONS

=cut

sub die_gracefully($) {

=head2 die_gracefully ( $message )

 die_gracefully($message)

Used for exiting the program, kind of a nice out, before the program exits it writes the log file, and possibly send an email

=cut

	#Messages to write
	$_ = shift;
	$! = 1;
	my $msg = "$_ \n" . "$!";

	#    print STDOUT $msg;
	$log->error("$msg\n");
	&notify($msg);
	$g_retval++;
	die "\nERROR: $_\n";
}

sub running_local() {

=head2 running_local ( )

 running_local()

used to check if we are running on ClearCase LT and the -host switch is defined, if this
is the case we will exit with an error.

To look for ClearCase LT we use the output from cleartool -ver.
The reply will include the string Rational ClearCase LT

Parameters: None
Returns:    None

=cut

	&debug_print("Entering sub running_local");
	my $cmd = "cleartool -ver";
	my $tmp = `$cmd`;

	if ( $tmp =~ /ClearCase LT/i ) {
		$flag_lt = 1;
		$log->information("$Scriptfile executing on Clearcase LT\n");
		&debug_print("sub running_local found that we are on Clearcase LT");
	}
	else {
		$log->information("$Scriptfile executing on Clearcase\n");
		&debug_print("sub running_local found that we are standard Clearcase");
	}
}

sub verify_switches {

=head2 verify_switches ( )

 verify_switches()

Takes all the Switches and checks if they are given in the right context.
Dies telling the error, if any of the switches arent given in the right syntax
or context.

Parameters: None
Returns:    Nothing

=cut

	&debug_print("Entering sub verify_switches");

	# Check if the switches are applied correctly:
	# If the rules of GetOptions aren't met, then abort.
	my $msg = "Aborting due to wrong use of options\n";
	unless ($optres) {
		&die_gracefully("$msg\n$usage");
	}

	#
	$msg = "Robocopy.exe is required\n";
	die_gracefully("$msg\n$usage") unless ( exists_robocopy() );

	#
	$msg = "reg.exe is required, but reg.exe was not detected\n";
	( exists_regexe() ) || ( die_gracefully("$msg\n$usage") );

	#
	$msg = "You must specify a target ...\n";
	defined($sw_target) || die_gracefully("$msg\n$usage");

	#
	$msg = "Must specify at least -vobs or -directory.\n";
	( !defined($sw_vobs) && !defined($sw_directory) )
	  && die_gracefully("$msg\n$usage");

	$msg = "Only a single source directory is allowed in dir-copy-mode.\n";
	( !defined($sw_vobs) && ( $sw_directory =~ /,/ ) )
	  && die_gracefully("$msg\n$usage");

	$msg = "-notify and -level are mutually dependent on each other\n";
	( ( defined($sw_notify) && defined($sw_level) ) || ( !defined($sw_notify) && !defined($sw_level) ) )
	  || die_gracefully("$msg\n$usage");

	#
	$msg = "-level must be one of I, W or E\n";
	defined($sw_level)
	  && do { $sw_level =~ /^[iIwWeE]$/ || die_gracefully("$msg\n$usage"); };

	#
	$msg = "Can't define -[no]depend unless -vobs is -all.\n";
	( ( !defined($sw_vobs) && defined($sw_depend) ) || ( defined($sw_vobs) && defined($sw_depend) ) && ( lc($sw_vobs) ne ("-all") ) )
	  && die_gracefully("$msg\n$usage");

	#
	$msg = "Can't use -livesync mode without -vobs \n";
	( ( defined($sw_livesync) ) && ( !defined($sw_vobs) ) )
	  && die_gracefully("$msg\n$usage");

	#
	$msg = "Can't use -[no]triggers without -vobs \n";
	( ( defined($sw_triggers) ) && ( !defined($sw_vobs) ) )
	  && die_gracefully("$msg\n$usage");

	#
	$msg = "Can't use -[no]database mode without -livesync \n";
	( ( defined($sw_database) ) && ( !defined($sw_livesync) ) )
	  && die_gracefully("$msg\n$usage");

}

sub expand_path($$) {

=head2 expand_path ( \$stringtoexpand, \$expandedstring )

 expand_path( \$stringtoexpand, \$expandedstring )

Expands a path string if valid template is found

Returns     0 on error
Returns     1 on success, a valid template was found

=cut

	debug_print("Entering sub expand_path");

	#validates if the template is valid
	# map it to a pattern usable to build a path

	my $input  = shift;
	my $output = shift;
	debug_print("\$\$input.\t[$$input]\n");

	my $valid   = 0;
	my $SECONDS = 60;
	my $diffseconds;
	my $epochnow  = time;
	my $epochthen = 0;

	if ( $$input =~ /(.*)<([Dd]{3})(.*)>(.*)/ ) {    # template matches short day pattern - we must expand
		my $base      = $1;
		my $modifier  = $3;
		my $remainder = $4;
		if ($modifier) {
			my ( $signed, $minutes ) = ( $modifier =~ /([-+])(\d+)/ );
			$diffseconds = ( $SECONDS * $minutes );
			if ( $signed eq '-' ) {
				$epochthen = $epochnow - $diffseconds;
			}
			else {
				$epochthen = $epochnow + $diffseconds;
			}
		}
		else {
			$epochthen = $epochnow;
		}

		my $wday = ( localtime($epochthen) )[6];
		my $day  = (WEEKDAYS)[$wday];
		$$output = "$base$day$remainder";
		$valid   = 1;
	}
	else {    # there's no expandabel keyword in the pathe - it's valid as it is
		$$output = $$input;
		$valid   = 1;
	}

	if ( $valid eq 0 ) {
		debug_print("Invalid template used in [$$input]");
		die_gracefully( "template is not valid " . $usage );
	}

	debug_print("\$\$output.\t[$$output]\n");
	return $valid;
}

sub validate_folder($) {

=head2 validate_folder ( \$dir_pname )

 validate_folder( \$dir_pname )

Test if folder exist.
Attempt creation if not dir and not exist

Parameter:        Reference to a string that should be a path

Return 1 on Success
Return 0 on Failure

=cut

	my $inpath = shift;
	my $dir    = $$inpath;

	( ( !-e "$dir" ) && ( !-f "$dir" ) ) && do {

		debug_print("The directory '$dir' does not exist: will attempt to create the directory\n");
		my $cmd       = "mkdir \"$dir\"  2>&1";
		my @stderrout = `$cmd`;
		my $retval    = ( ($?) / 256 );
		&debug_print("Executed: [$cmd] Return value was: [$retval]\n");
		if ($retval) {
			$log->error("Executed: [$cmd] Return value was: $retval\n");
			$log->error("\tcontent written to console was\n");
			foreach (@stderrout) {
				chomp;
				$log->error("\t$_\n");
			}
			return 0;
		}

		else {
			$log->information("Created directory: \"$dir\"\n");
			return 1;
		}
	};
	return 1;
}

sub initialize {

=head2 initialize ( )

 initialize()

Initialize simply initializes the environment we are working in.
The order of events is important.
Parameters:   None
Returns:      Nothing.

=cut

	# $g_retval caches the accumulated overall error state
	$g_retval = 0;

	#  Check if all switches are applied corretly according to the syntax
	verify_switches();

	# Initialise variables various preprocessing

	$host = $ENV{COMPUTERNAME};

	# Check if CC LT or not
	running_local();

	# Determine target path, expand it if there is template syntax

	if ( expand_path( \$sw_target, \$destination ) ) {
		$log->information("Path template [$sw_target] set to  [$destination]\n");
	}
	else {
		$log->error("Trouble expanding path template [$sw_target] \n");
	}

	#MUST DIE if we cant create destination folder:
	validate_folder( \$destination ) || die_gracefully("Failed to create the target folder [$destination]");

	# If logdir is undefined, assign default value
	!defined($sw_logdir) && do {
		$sw_logdir = $destination;
		&debug_print("\$sw_logdir set to default value [$sw_logdir]");
	};

	$log->information("Log directory set to $sw_logdir\n");

	# Validate log dir
	$g_retval = ( validate_folder( \$sw_logdir ) ) ? $g_retval : $g_retval++;

	# assign log file name

	$g_file = "$sw_logdir\\$Scriptfile.PID$$.log";

	# assign log file
	$log->set_logfile($g_file);

	# start logging
	# We MUST DIE if wi can't enable the log.
	$log->enable() || die_gracefully("Failed to enable log [$sw_logdir\\$Scriptfile.PID$$.log]");

	# fixed robocopy parameters, don't change unless you know the consequences
	$robocopy_params = "/E /COPYALL /MIR /SEC /R:5 /A-:A";

	# -depend and -database are default values, enable if undefined
	$sw_database = defined($sw_database) ? $sw_database : 0;    # default is -nodatabase
	$sw_depend   = defined($sw_depend)   ? $sw_depend   : 1;    # default is -depend
	$sw_triggers = defined($sw_triggers) ? $sw_triggers : 1;    # default is -triggers

	# Log version number
	$log->information("Script: $Scriptfile Version $VERSION.$BUILD \n");

	# Override $robocopy_params if requested via switch
	if ( defined($sw_robocopy) ) {
		$robocopy_params = $sw_robocopy;
		$log->warning("NON default robocopy parameters: \"$robocopy_params\", you are on your own !\n");
	}
	else {
		$log->information("Robocopy parameters: \"$robocopy_params\"\n");
	}

	if ( defined($sw_vobs) ) {

		# vobs are requested for backup, Find vobs to process
		@voblist = &get_thevobs();
		$log->information( "Vobs requested for backup: " . join( ',', @voblist ) . "\n" );
		if ( -e "$destination" ) {

			# Remove obsolete files in destination, but leave "vobs" folder
			$log->information("Backup target exists, removing all files except vobs and logfile\n");

			my @destinationfiles = `dir /b $destination`;
			foreach (@destinationfiles) {
				chomp;
				my $item = "$destination\\$_";
				if ( ( lc($_) eq "vobs" ) and -d "$item" ) {
					next;    # don't delete "vobs" directory
				}
				if ( $item eq $g_file ) {
					next;    # leave current logfile

				}
				if ( -d "$item" ) {
					`rmdir /S /Q \"$item\"`;    # Remove any other directory
					( ($?) / 256 ) && $log->warning("Trouble removing \"$item\"\n");
				}
				if ( -f "$item" ) {
					`del /F /Q \"$item\"`;      # Remove any other file
					( ($?) / 256 ) && $log->warning("Trouble removing \"$item\"\n");

				}
			}

		}
	}
	else {
		$log->information("No vobs requested for backup, destination \"$destination\" not cleared before copy\n");
	}

}    # end sub initialize

sub exists_robocopy {

=head2 exist_robocopy ( )

 exist_robocopy()

Test if robocopy.exe is available and if it is the version that has been
tested with this script

Parameters: None
Returns:    0 if not found (error)
Returns:    1 if found (OK)

=cut

	my $neededversion = "XP010";

	my $found = grep /$neededversion/, `robocopy 2\>\&1`;
	return $found;

}

sub notify() {

=head2 notify ( )

 notify()

Used to send emails to a given list of recipients, the email will contain log information,
there are tree option on notify [I|W|E]

 I) gives all the information the script has. (LIKE IN SPAM).
 W) gives all the warnings created under the run.
 E) gives all the errors created under the run.


=cut

	# This function will send the log file to recipients
	debug_print("Entering notify()\n");
	my $runningfile = $log->get_logfile;
	if ( -e $runningfile ) {
		open( LOG, "< $runningfile" ) or die "can't open $runningfile: $!";
		push @g_notify, $_ while <LOG>;
		close LOG;
	}
	if ( scalar(@g_notify) && defined($sw_notify) ) {

		# Create end note, telling about the location of the complete log
		my $infolevel;
		my $subscribeerrlvl = -1;
	  SWITCH: {
			$sw_level =~ /[Ii]/
			  && do {
				$infolevel       = "All information (-level $sw_level).";
				$subscribeerrlvl = 0;
			  };
			$sw_level =~ /[Ww]/
			  && do {
				$infolevel       = "Warnings (-level $sw_level).";
				$subscribeerrlvl = 1;
			  };
			$sw_level =~ /[Ee]/
			  && do {
				$infolevel       = "Errors (-level $sw_level).";
				$subscribeerrlvl = 2;
			  };
		}

		my $recipients = join " ", split ",", $sw_notify;
		my $notify_file = "$destination\\$date.notify";
		debug_print("\$notify_file\t$notify_file\n");
		open( NOTIFY, ">$notify_file" ) or $log->error("Failed opening notify file $notify_file\n");

		print NOTIFY "##############################################################################\n";
		print NOTIFY "##\tNOTE\n";
		print NOTIFY "##\tYou have subscribed to be notified about $infolevel\n";
		print NOTIFY "##\tThe complete log is stored on:\n";
		print NOTIFY "##\t$ENV{COMPUTERNAME} at \"$sw_logdir\"\n";
		print NOTIFY "##############################################################################\n";
		print NOTIFY "\n";

		# Pour the message array into the notify file
		foreach $_ (@g_notify) {
			print NOTIFY "$_";
		}
		close NOTIFY;

		debug_print("Content of \@g_notify\n");
		$g_debug && do {
			print STDERR "<BOF>\n";
			foreach $_ (@g_notify) { print STDERR $_ . "\n"; }
			print STDERR "<EOF>\n";
		};
		my $status = ($g_retval) ? "FAILURE" : "SUCCES";

		# NOTIFY.EXE
		# If you rather want to use notify installed together with ClearCase and configured through the cc.cpl, and yet
		# both undocumented and unsupported by IBM (...!)
		# Yau can use the statement below:
		#        my $cmd       = "notify -s \"CCBACKUP [$status]\" -f \"$notify_file\" $recipients 2\>\&1";

		#At this point query the log about the overall errerstate and send notification accordingly.

		my $totalerrlvl = $log->get_accumulated_errorlevel();

		&debug_print("\$subscribeerrlvl:\t$subscribeerrlvl\n");
		&debug_print("\$totalerrlvl:\t$totalerrlvl\n");

		if ( $totalerrlvl >= $subscribeerrlvl ) {

			# Please NOTE that it's assumed that blat is correctly installed and configured.
			# If this is not the the case, it will cause the script to give a returnvalue that indicates an error ($retval>0)
			# BLAT:EXE
			my $cmd = "blat \"$notify_file\" -s \"CCBACKUP [$status]\" -to $sw_notify 2\>\&1";

			my @stderrout = `$cmd`;
			my $retval = ( ($?) / 256 );
			&debug_print("Executed: [$cmd] Return value was: [$retval]\n");
			if ($retval) {
				$log->error("Executed: [$cmd] Return value was: $retval\n");
				$log->error("\tcontent written to console was\n");
				foreach (@stderrout) {
					chomp;
					$log->error("\t$_\n");
				}
			}
		}
	}
}

sub want_help {

=head2 want_help( )

 want_help()

Used to check if the scripter is needing assistance.

=cut

	if ( defined($sw_usage) )   { print "$usage\n";    exit(0) }
	if ( defined($sw_help) )    { print "$helpmsg\n";  exit(0) }
	if ( defined($sw_version) ) { print "$revision\n"; exit(0) }
}

sub enable_debug {

=head2 enable_debug( )

 enable_debug()

enables the "debug mode" which means the script will load all information
to STDOUT(LIKE IN SPAM).

=cut

	$g_debug = 0;    #Used for debugging

	#        Initializes the global variable $g_debug
	#        1) If the environment variable "trace_subsys" contains the name of this script.
	#        2) If the environment variable ccdebug is defined
	#        3) If the debug switch is applied
	$_ = lc($Scriptfile);

	#look for the name of the perl script in "trace_subsys"
	if ( lc( $ENV{trace_subsys} ) ) {
		$g_debug = 1;
	}

	#Look for the environment variable "ccdebug"

	#Look for the environment variable "ccdebug"
	if ( $ENV{ccdebug} ) {
		$g_debug = 1;
	}

	#Check if the debug switch is used.
	if ( defined($sw_debug) ) {
		$g_debug = 1;
	}

	if ($g_debug) {
		print "Running in debug mode\n" . "-------------------------------------------------------------\n";

		my $cmd         = "set";
		my $ccvariables = `$cmd`;
		print "Environment Variables:\n"
		  . "-------------------------------------------------------------\n"
		  . $ccvariables
		  . "-------------------------------------------------------------\n";
		print "Script Options [\$optres = $optres]:\n" . "-------------------------------------------------------------\n";
		foreach my $key ( sort keys %options ) {
			my $value = $options{$key};
			if ( defined($$value) ) {
				print "$key => [$$value]\n";
			}
			else {
				print "$key => UNDEFINED\n";
			}
		}
		print "-------------------------------------------------------------\n";
	}
}

sub debug_print($) {

=head2 debug_print ( $message )

 debug_print( $message )

Used to actually print all the messages out to STDOUT it will alwas run but before printing
it checks to see if this script is running in debug mode.

=cut

	if ($g_debug) {
		my $str = shift;
		chomp $str;
		my $msg = "\t    DEBUG::  $str\n";
		print STDERR $msg;
	}
}

sub copy_vob_stg($) {

=head2 copy_vob_stg ( $vobtag )

 copy_vob_stg($vobtag)

This sub functinon will copy the storage of a VOB to the target
1st parameter is the VOB

Returns:
        0 on success.
        other than 0 on failure.

=cut

	my $vob = shift;
	debug_print("Entering sub: copy_vob_stg($vob)\n");
	my ($vobstg);
	my $retval    = 0;
	my $cmd       = "cleartool lsvob $vob 2\>\&1";
	my $stderrout = `$cmd`;
	debug_print( "Executed: [$cmd] Return value was: [" . scalar($?) / 256 . "]\n" );

	if ( $stderrout =~ /[*\s]\S+\s+(\S*)/ ) {    # Looking for VOBTAG VOBSTG
		my $match = "$1";
		debug_print("\$match:\t$match\n");
		if ( $match =~ /^\\\\.+/ ) {             # Detected a UNC path (gpath)
			$vobstg = $match;
		}
		else {                                   # Could be that we're running on ClearCase LT

			if ( $match =~ /^(\S+?):(\S+)/ ) {    #Looking for HOST:LOCALPATH
				$host   = $1;
				$vobstg = $2;
				debug_print("Detected ClearCase LT gpath syntax:\n");
				debug_print("host:\t$host\n");
				debug_print("vobstg:\t$vobstg\n");
				if ( lc($host) ne lc( $ENV{COMPUTERNAME} ) ) {
					$log->error("$Scriptfile Won't process vob $vob located on remote host $host.\n");
					return 1;                     # Return error.
				}
			}
			else {

				# We could neither find vob storage from ClearCase or ClearCase LT return formats
				# so we appear to be in serious trouble. Save as much information as possible and die.
				my $msg = " We could neither find vob storage from ClearCase or ClearCase LT return formats \n";
				$msg = "$msg \tERROR: Executed: [$cmd]\n";
				$msg = "$msg \tReturn value was: [" . scalar( ($?) / 256 ) . "]\n";
				$msg = "$msg \tcontent written to console was\n";
				$msg = "$msg \t$stderrout \n";
				&die_gracefully($msg);
			}
		}
		my $vobtargetroot = $destination;

		# Determined VOB storage now get the target and final-target

		if ( $vobstg =~ /.+\\(\S+)$/ ) {
			my $vobtarget = $1;
			debug_print("\$vobtarget:\t$vobtarget\n");

			my $finaltarget = $vobtargetroot . "\\vobs\\" . $vobtarget;
			&debug_print("Final target:\t$finaltarget\n");

			# make the copy
			$cmd = "robocopy $vobstg $finaltarget $robocopy_params 2\>\&1";

			$log->information("Will copy \"$vobstg\" to \"$finaltarget\"\n");
			my @stderrout = `$cmd`;
			$retval = scalar($?) / 256;
			&debug_print("Executed: [$cmd] Return value was: [$retval]\n");

			# report the result
			# if robocopy returns 8 or higher it is bad, else is ok
			if ( $retval < 8 ) { $retval = 0; }

			if ($retval) {
				$log->error("Executed: [$cmd] Return value was: $retval\n");
				$log->error("\tcontent written to console was\n");
				foreach (@stderrout) {
					chomp;
					$log->error("\t$_\n");
				}
			}
			else {
				$log->information("Succesfully backed up vob:$vob\n");
			}
		}

		else {    # Failed to retrieve the leaf folder name (typically *.vbs) from the vob storage
			my $msg = "ERROR: Could not get determine foldername from \"$vobstg\"";
			&die_gracefully($msg);
		}
	}
	else {        # Recieved a different format form the cleartool lsvob command than expected!
		my $msg = "ERROR: Executed: [$cmd] Return value was: [" . scalar($?) / 256 . "] content written to console was:\n" . $stderrout;
		&die_gracefully($msg);
	}
	return $retval;
}

sub do_the_lock($$$$) {

=head2 do_the_lock( $vobtag, $mode, \$nuserswitch, \$lockcomment )

 do_the_lock( $vobtag, $mode, \$nuserswitch, \$lockcomment )

A lock on a vob can have 4 flavours:

=item *

a) unlocked (not locked)

=item *

b) locked (locked for everybody

=item *

c) locked -nuser name1,... (locked except for name1,...)

=item *

d) locked -obsolete (locked for all, an not hidden from GUI

=back

This function will lock or unlock the VOB as required
In lock mode it will detect and cache the current lock type, as well as the lock
comment, if it exist.
In unlock mode the previous setting will be reapplied.


=item *

1st parameter is the VOB

=item *

2nd parameter is the mode: lock|unlock

=item *

3rd parameter is a reference to the nuser list

=item *

4th parameter is a reference to the existing lock comment

=back
Returns 0 if success otherwise an integer different from 0

=cut

	my $vob       = shift;
	my $mode      = lc(shift);
	my $nuserlist = shift;
	my $cmnt      = shift;

	my $retval = 1;    # Default return is error, we must have success to return sucess.
	my $msg;

	debug_print("Entering sub do_the_lock($vob, $mode, $$nuserlist, $$cmnt)\n");    ######################

	if ( $mode =~ /lock|unlock/ ) {                                                 # continue only if mode is understood.
		my $cmd           = "cleartool desc -fmt \"\%[locked]p\" vob:$vob";
		my $locked_status = `$cmd`;                                                 # locked | unlocked | obsolete
		my ( $ignore, $action, $replace, $nuser, $lockcomment );

		$action      = $mode;
		$lockcomment = "-c \"$action set by $Scriptfile\"";

		if ( $locked_status eq "locked" ) {

			my $cmd       = "cleartool lslock -fmt %Nc vob:$vob 2>&1";
			my @stderrout = `$cmd`;
			my $comment;

			if ( lc($mode) eq "lock" ) {

				# Already locked. Look for -nuser
				# Cache -nuser and comment if there.
				for ( my $i = 0 ; $i <= $#stderrout ; $i++ ) {
					if ( $i == 0 ) {
						if ( $stderrout[$i] =~ /:/ ) {

							# reply if locked -nuser looks like "Locked except for users: kim ingrid kaj", note the colon
							$stderrout[$i] =~ /(.*: )(.*)/;    # isolate user list
							( my $userlist = $2 ) =~ s/\s+/,/g;    # separate list with comma's
							$$nuserlist = $userlist;               # update reference
							debug_print("-nuser list calculated to: [$userlist]\n");
							next;
						}
						else {                                     # First line did not list -nuser's
							next;
						}
					}
					my $line = $stderrout[$i];

					# There is a bug in CC, we can't apply multiline lock comments
					# from CLI again, so we have to flatten it to a single line.
					# Multiline lock comments are possible from the GUI, but not
					# much help in CLI.
					$line =~ s/[\cM|\cJ]//g;                       # strip control codes
					$comment = "$comment$line ";
				}

				# cache that comment

				$$cmnt = $comment;
				debug_print("Original lock comment cached: [$comment]\n");

######################
				if ($$nuserlist) {

					$replace = "-replace";
					$nuser   = "";
					$log->information("The vob $vob is locked with -nuser list. Must lock for all users while backing up\n");

				}
				else {
					$ignore = 1;    # Don't change the lock
					$retval = 0;
					$log->information("The vob $vob is already locked, Request to $mode can be ignored\n");

				}

			}
			else {                  # mode is unlock

				if ($$nuserlist) {

					# was locked -nuser, replace lock
					$log->information("Status $locked_status and mode $mode, found $$nuserlist, replacing lock with -nuser list\n");
					$action      = "lock";
					$replace     = "-replace";
					$nuser       = "-nuser $$nuserlist";
					$lockcomment = "-c \"$$cmnt\"";        # reuse original lock comment
				}
				else {
					if ( $$cmnt !~ /$Scriptfile/ ) {
						$ignore = 1;                       # Don't change the lock
						$retval = 0;
						$log->information("$vob was not locked by $Scriptfile, Ignoring $mode request\n");
					}    # end if ($$cmnt !~ /$Scriptfile/ )
				}    # end if  ($$nuserlist)
			}    # end if         (lc($mode) eq "lock")
		}
		elsif ( $locked_status eq "obsolete" ) {

			$ignore = 1;    # Don't change the lock
			$retval = 0;
			$log->information("Attempt to $mode vob:$vob, but it was locked obsolete (The $mode operation will be ignored)\n");
		}
		elsif ( $locked_status eq "unlocked" ) {

			if ( lc($mode) eq "lock" ) {
				$$cmnt = $lockcomment;

			}
			else {
				$lockcomment = "-nc";
				$log->warning(
					"Attempt to $mode vob:$vob,
                    but it is already $locked_status (The $mode operation will be ignored
                    Look for previous warnings or errors\n"
				);
			}

		}
		else {
			$log->error("Status of lock [$locked_status] not expected\n");
		}

		#        Execute the lock or unlock as required (if we really have to)
		if ($ignore) {    # don't change the lock
			$retval = 0;
		}
		else {

			# Finalize command string
			$cmd = "cleartool $action $replace $nuser $lockcomment vob:$vob 2>&1";

			my $stderrout = `$cmd`;
			chomp($stderrout);

			debug_print( "Executed: [$cmd] Return value was: [" . scalar( ( $? / 256 ) ) . "]\n" );

			if ($?) {

				$log->error("$stderrout\n");
			}
			else {

				$log->information("$stderrout\n");
			}
			$retval = scalar( ( $? / 256 ) );

		}
	}
	else {    # Mode not understood
		$log->error("sub do_the_lock did not understand  \$mode [$mode]\n");

	}

	return $retval;
}

sub get_adminvob($) {

=head2 get_adminvobs( $vobtag )

 get_adminvos($vobtag)

Finds the VOBTAG´s admin vob. A admin vob is defined with theire vobtag
includes "(AdminVob)"

Returns the admin vob´s VOBTAG for the vob given as a parameter.

=cut

	my $vob = shift;
	my $retval = join "", get_hlinks( $vob, "->", "AdminVOB" );
	if ( $retval eq "" ) {
		return $vob;
	}
	else {
		return &get_adminvob($retval);
	}
}

sub get_hlinks($$$) {

=head2 get_hlinks( \$Object, \$Direction, \$HLType )

 get_hlinks (\$Object, \$Direction, \$HLType).

Object:     is the object that are check for hyperlinks.
Direction:  Which way the hyperlink that are looked for should turn.
HLType:     Indicates wich type of hyperlink there should be looked for.

=cut

	my $obj       = shift;
	my $direction = shift;
	my $hltype    = shift;
	my @retval;
	my $cmd = "cleartool desc -ahlink $hltype $obj";
	my $res = `$cmd`;
	foreach my $ln ( split /\n/, $res ) {
		if ( $ln =~ /\s*$hltype\s*$direction\s*(.*)\s*$/ ) {
			push @retval, $1;
		}
	}
	return @retval;
}

sub unique {

=head2 unique( )

Get unique values, return as array or comma-separated list

=cut

	my ( $input, $mode ) = @_;
	my %seen = ();
	my @unique = grep { !$seen{$_}++ } @$input;
	if ( lc($mode) eq "csv" ) {
		chomp @unique;
		my $csv = join( ",", @unique );
		return $csv;
	}
	return @unique;
}

sub do_triggers($) {

=head2 do_triggers( $vobtag )

 do_trigger($vobtag);

A vob isn't much worth wihtout the triggers to define the use of the VOB there
this sub takes care of backing up the trigger for the given VOB.

Returns:
        0 on succes.
        Non-zero on failure.

=cut

	# Backup vob triggers and any files listed fully qualified in trigger action.
	my $vobtag = shift;
	my $retval = 1;

	#    Triggerbackup, must save to trigger_files\vobtag\triggername subfolde
	my $finaltarget = "$destination\\triggers" . $vobtag;

	my $cmd = "cleartool lstype -kind trtype -s -invob $vobtag";
	&debug_print("Executing command [$cmd]");
	my @triggerlist = `$cmd`;

	if (@triggerlist) {
		$log->information("#     Backing Triggers in $_      #\n");
	}
	else {
		$log->information("#     No triggers to backup in $_      #\n");
	}

	foreach my $trigger (@triggerlist) {
		$trigger =~ s/"(.*)"$/$1/;
		chomp $trigger;
		my $target = "$finaltarget\\" . uc($trigger);
		&debug_print("Executing command [mkdir $target]");
		if ( !-e "$target" ) {
			`mkdir \"$target\"`;
			( ($?) / 256 )
			  && $log->error("Trouble creating trigger output dir \"$target\"\n");
		}

		# Save trigger description
		$cmd = "cleartool desc -l trtype:$trigger\@$vobtag";
		debug_print("Executing command [$cmd]");
		my @description = `$cmd`;

		my $file = "$trigger.txt";
		$file = "$target" . "\\$file";

		open( TRIGGERFILE, ">$file" ) || do {
			my $msg = "Can't open output file $file: $!";
			$log->error("$msg\n");
		};
		my $msg = "Saving trtype:$trigger\@$vobtag to $target\n";
		$log->information("$msg");
		&debug_print($msg);
		foreach (@description) {
			print TRIGGERFILE $_;
		}
		close(TRIGGERFILE);

		# Isolate trigger executable action
		my $action;
		foreach (@description) {

			if ( $_ =~ /action:.*-exec\S*\s*\S*\s*(.*)/ ) {
				$action = $1;
			}
		}

		if ( ( !-e "$action" ) || ( !-f "$action" ) ) {

			# It can be discussed if this should be logged as information or warning. choosing information for now.
			$log->information("Can't find find a file at \"$action\"\n");
			$log->information("Action execution: \"$action\" has not been copied to a file.\n");
			next;
		}

		$cmd = "xcopy /Q /Y $action \"$target\" 2\>\&1";
		debug_print("Executing [$cmd]");
		my @stderrout = `$cmd`;
		$retval = ($?) / 256;
		if ($retval) {
			debug_print("xcopy returns an error, the return level was $retval\n");
			my $msg = "Could not copy scrppt file [$action] for trigger [$trigger\@$vobtag]";
			$log->error("$msg\n");
			chomp @stderrout;
			foreach (@stderrout) {
				$log->error("XCOPY ERROR:\t $_\n");
			}
		}
	}
	return $retval;
}

sub exists_regexe() {

=head2 exists_regexe( )

 exists_regexe()

Attempt to execute reg.exe.
If not available the arraysize is low

Parameters:        None

Returns 0 if unable to find
Returns 1 if found (success)

=cut

	chomp( my @head = `reg 2\>\&1` );
	if ( $#head < 2 ) { return 0 }
	return 1;
}

sub export_winrgy {

=head2 export_winrgy( )

 export_winrgy()

export_winrgy exports Clearcase specific registry information.
The export depends on reg.exe which is a system utility on
Win XP (or server 2003) but otherwise it can be optained as part of
the Windows Server Ressource Kit

The default keys are always exported, by if switch -winrgy does not contain
the word clearcase, the option is assumed to designate more keys that then
will be added to the keys.

Each key and all it's subkeys are being exported.

If reg.exe encounters problems, an error message is written to the log, but the
script will continue.

Parameters:        None
Returns Nothing

=cut

	my $outpath = "$destination\\registry_files";
	my @result;

	my @defaultkeys = (
		'HKEY_CURRENT_USER\Environment',
		'HKEY_CURRENT_USER\Software\Atria\ClearCase',
		'HKEY_LOCAL_MACHINE\SOFTWARE\Atria\ClearCase',
		'HKEY_LOCAL_MACHINE\SOFTWARE\Flexlm License Manager',
		'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AeDebug',
		'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems',
		'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Windows',
		'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\LanManWorkstation\Parameters',
		'HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\MRXSmb\Parameters'
	);

	# Add additional keys requested on command line
	if ( lc($sw_winrgy) ne "clearcase" ) {
		push( @defaultkeys, split( /,/, $sw_winrgy ) );
	}

	if ( !-e "$outpath" ) {
		`mkdir \"$outpath\"`;
		( ($?) / 256 )
		  && $log->error("Trouble creating trigger output dir \"$outpath\"\n");
	}

	foreach (@defaultkeys) {

		( my $file = $_ ) =~ s/\\/./g;    #Create export file name by replacing backslash with dot
		my $cmd = "reg export \"$_\"  \"$outpath\\$file.reg\" 2>&1";
		&debug_print("Attempting registry export command: [$cmd]");
		$log->information("Exporting REG key $_ to $file\n");
		$log->information("\tto \"$outpath\\$file.reg\"\n");
		push( @result, `$cmd` );
		( $? / 256 ) && $log->error("Trouble exporting registry key $_\n");
	}

}

sub get_thevobs {

=head2 get_thevobs( )

 get_thevobs()

Get all vobs on host
Return array of vobs on this host.


=cut

	my @allvobs;

	# is sw_vobs all" switch was used)
	if ( lc($sw_vobs) eq "-all" ) {

		debug_print("SUB sortvoblist found that vobs \"-all\" is defined");
		@allvobs = `cleartool lsvob`;
	}
	else {

		# A CSV string a vobtags in $sw_vobs
		debug_print("SUB sortvoblist parses \$sw_vobs which is found that vobs: [$sw_vobs] is defined");
		my @tags = split( /,/, $sw_vobs );
		foreach (@tags) {

			system("cleartool lsvob $_ >nul 2>1");
			if ($?) {
				$log->error("The VOB named [$_] doesn't exist\n");
			}
			else {
				push @allvobs, qx(cleartool lsvob $_);
			}
		}
	}

	# chop 2 leading char's (could be '* ' or '  '
	foreach (@allvobs) {
		$_ =~ s/(..)(.*)/$2/;
	}

	# sort the array
	@allvobs = ( sort @allvobs );

	#    print "IN sub sortvoblist \@allvobs is now\n @allvobs";

	# Only for base Clearcase:
	unless ($flag_lt) {

		#        print "Base Clearcase, skipping vobs not on host\n";

		foreach (@allvobs) {
			if ( lc($_) =~ /\\\\$host\\/i ) {
				push @_, $_;
			}
			else {
				chomp;
				$log->error("Ignoring vob [$_] as it is not local to [$host]\n\n");
			}
		}
		@allvobs = @_;

		#        print @allvobs;
	}

	foreach (@allvobs) {    # Vobtag only

		$_ =~ s/(\S+)(\s+.*)/$1/;
		chomp;
	}
	return @allvobs;
}    # end sub sortvoblist

sub do_directories {

=head2 do_directories

 do_directories()

Copy directories

Parameters: none

Return 0 on Successfull copy
Return 1 on failure

=cut

	my $notrecursive = "/LEV:1 /COPYALL /MIR /SEC /R:2 /A-:A /W:5 ";    # robocopy will only copy 1'st level subdir's a.k.a not recursive
	my @dirs = split( /,/, $sw_directory );

	foreach my $dir (@dirs) {

		$log->information("Processing [$dir] for directory copy\n");

		# see if the requested directory can be expanded by keyword
		my ( $copy_from, $copy_to, $copyswitches, $builtpath );

		if ( &expand_path( \$dir, \$copy_from ) ) {
			$log->information("Source: [$dir] expanded to [$copy_from]\n");
		}
		else {
			$log->error("Trouble expanding Source dir: [$dir]\n");
		}

		# Determine if we should do recursive copy and normalize source path string
		if ( $copy_from =~ /.*(\\\*$)/ ) {    # path ends with asterisk, do recursive copy
			$copyswitches = $robocopy_params;    # Use the normal robocopy parameters (mirror mode)
			$copy_from =~ s/(.*)(\\\*$)/$1/;     # remove trailing backslash and asterisk
		}
		else {
			$copyswitches = $notrecursive;       # Use robocopy parameters so recursive copy is only 1 level deep.
		}

		if ( !$sw_vobs ) {
			$copyswitches = $robocopy_params;    # Use the normal robocopy parameters (mirror mode), in copy-only mode
		}

		# Source determined, including expansion, next if it does not exists
		if ( ($sw_vobs) && !-e $copy_from || !-d $copy_from ) {
			$log->warning("Directory [$copy_from] was not found, ignoring copy request \n");
			next;
		}

		#
		if ( defined($sw_vobs) ) {               # vob-copy mode

			$builtpath = $copy_from;             # build a subdirectory path
			$builtpath =~ s/\://g;               # weed out colon
			$builtpath =~ s/^\\\\/\\/;           # Change lead double backslash to one

			$copy_to = "$destination\\external_dirs\\$builtpath";
		}
		else {                                   # dir-copy mode

			$copy_to = "$destination";

		}

		my $cmd = "robocopy \"$copy_from\" \"$copy_to\" $copyswitches ";
		&debug_print("Executing:\t $cmd");
		my @stderrout = `$cmd`;

		# if robocopy returns 8 or higher it is bad, else is ok
		if ( ( ($?) / 256 ) < 8 ) {
			$log->information("Succesfully copied [$copy_from]\n");
		}
		else {
			$log->error("Problems copying [$copy_from] \n");
			chomp @stderrout;
			foreach (@stderrout) {
				$log->information("ROBOCOPY SAID:\t $_ \n");
			}
		}

	}
}

__END__
