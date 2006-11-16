require 5.000;
use strict;

BEGIN {

	# Ensure that the view-private file will get named back on rejection.
	END {
		rename( "$ENV{CLEARCASE_PN}.mkelem", $ENV{CLEARCASE_PN} )
		  if $? && !-e $ENV{CLEARCASE_PN} && -e "$ENV{CLEARCASE_PN}.mkelem";
	}
}

#Getting the script dir
our ( $Scriptdir, $Scriptfile );

BEGIN {
	if ( __FILE__ =~ /(.*[\/\\])(.*)$/ ) {
		$Scriptdir  = $1;
		$Scriptfile = $2;
	}
	else {
		$Scriptdir  = "";
		$Scriptfile = __FILE__;
	}
}

use File::Basename;
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
our $REVISION = "33";

my $verbose_mode = 0;    # Setting the verbose mode to 1 will print the logging information to STDOUT/ERROUT ...even it the log-file isn't enabled
my $debug_on = defined( $ENV{'CLEARCASE_TRIGGER_DEBUG'} ) ? $ENV{'CLEARCASE_TRIGGER_DEBUG'} : undef;

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
2010-03-03  Jens Brejner   Fixed double printed message (v1.0.27)
2010-03-03  Jens Brejner   Build commands to merge the name forward,
                           save them in logfile (v1.0.29)
2010-05-31  Jens Brejner   Enhance error checking after system calls (v1.0.30)
2010-08-06  Jens Brejner   Fixed bug - could not handle path that
                           contained "\c\", as it was considered a control char.
                           now using File::Basename instead of split_dir_file. (v1.0.31)
2011-04-06  Jens Brejner   Add external config file dependency (v1.0.32)

-------------------------  ----------------------------------------------

ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;

# Look for semaphore, respecting a local semaphore path via env. var.
our $semaphore_status = $thelp->enable_semaphore_backdoor( $ENV{'CLEARCASE_USE_LOCAL_SEMAPHORE'} );

# Initiate logging.
our $log = scriptlog->new;
$log->conditional_enable();    #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose;             #Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
($logfile) && $log->information($semaphore_status);
($logfile) && $log->dump_ccvars;                              # Run this statement to have the trigger dump the CLEARCASE variables

# Script scope variables
my (
	%twincfg,    $case_sensitive, $viewkind, $pathname,     $sfx,   $pop_kind, $user,    $parent,       $element,
	$parent_dna, $pattern,        %added,    %uncatalogued, $found, $info,     $warning, $pre_proc_bat, $post_proc_bat
);

# Read optional local configuration of trigger

$thelp->get_config( \%twincfg );
$case_sensitive = $twincfg{CaseSensitive};
$viewkind       = $ENV{CLEARCASE_VIEW_KIND};
$pathname       = $ENV{CLEARCASE_XPN};
$sfx            = $ENV{CLEARCASE_XN_SFX} ? $ENV{CLEARCASE_XN_SFX} : '@@';
$user           = $ENV{CLEARCASE_USER};
$pop_kind       = lc( $ENV{CLEARCASE_POP_KIND} );

# continue only if operation type is what we are intended for..
if ( lc( $ENV{'CLEARCASE_OP_KIND'} ) eq "lnname" ) {

	# Here starts the actual trigger code.
	name_lookup();

	# No duplicate element is found on invisible branches
	# Allow the creation of the element.
	exit 0 unless $found;

	build_primary_message();
	exit 1 unless $twincfg{AutoMerge};

	# Prepare commands to fix the situation

	# Done our best, inform and get out

	if ( $twincfg{AutoMerge} == 0 ) {

		# Inform only, and stop the operation
		exit 1;

	}

	if ( $twincfg{AutoMerge} == 1 ) {

		# Do the required merge, but leave checked out
		foreach (@mkmerge) {
			print "$_\n";
			my $retval;
			qx($_);
			if ($?) {
				$log->error("The command [$_] didn't exit properly: $retval");
				die "ERROR. Read the logfile\n";
			}

		}
		$log->warning(
			"Evil twin detected. 
We have tried to get around it, but haven't checked in the changes. 
Please verify, and check in if you are satisfied"
		);
		exit 1;

	}

	if ( $twincfg{AutoMerge} == 2 ) {

		# Do the required merge and check in
		foreach ( ( @mkmerge, @mkci ) ) {
			my $retval = qx($_);
			if ($?) {
				$log->error("The command [$_] didn't exit properly: $retval");
				die "ERROR. Read the logfile\n";
			}

		}
		$log->information("Evil twin detected. We have tried to get around it, we hope you are happy with it.");
		exit 0;

	}

	# Prevent the OP anyway - should we ever end here
	exit 1;

}

sub build_fixcommands {

	my ( $fixcmd, $tmpfilename, $foundpath, @head, @mkmerge, @mkci, @exit );

	$tmpfilename = time();
	$foundpath   = $parent_dna . $added{$element};

	( my $win32parent    = $parent )    =~ tr#/#\\#;
	( my $win32foundpath = $foundpath ) =~ tr#/#\\#;
	( my $win32element   = $element )   =~ tr#/#\\#;
	my $cwd = `cd`;

	@head = ( <<"END_OF_HEAD" =~ m/^\s*(.+)/gm );
The proper way to correct the situation, is to re-introduce the name
$win32element in the directory by executing the following commands in order:

END_OF_HEAD

	@mkmerge = ( <<"END_OF_MKMERGE" =~ m/^\s*(.+)/gm );
REM BATCH START
pushd  \"$win32parent\"
rename \"$win32element\" $tmpfilename
cleartool co -nc .
cleartool merge -graphical -qall -c \"Re-introducing the name $element\" -to . \"$win32foundpath\"
cleartool co -nc \"$win32element\"
copy /y  $tmpfilename  \"$win32element\"
popd

END_OF_MKMERGE

	@mkci = ( <<"END_OF_MKCI" =~ m/^\s*(.+)/gm );
pushd  \"$win32parent\"
cleartool ci -nc \"$win32element\"
cleartool ci -nc .
popd

END_OF_MKCI

	($logfile) && $log->information( join '\n', ( @head, @mkmerge, @mkci ) );
	$pre_proc_bat = "$parent/pre_$tmpfilename.bat";
	$post_proc_bat = "$parent/post_$tmpfilename.bat";
	open( PREBAT,  "> $pre_proc_bat" )  or die "Couldn't open $pre_proc_bat for writing: $!";
	open( POSTBAT, "> $post_proc_bat" ) or die "Couldn't open $post_proc_bat for writing: $!";

	foreach (@head)    { print PREBAT "REM $_"; }
	foreach (@mkmerge) { print PREBAT "$_"; }
	foreach (@mkci)    { print POSTBAT "$_"; }

	close( PREBAT, POSTBAT );

}

sub build_primary_message {

	$log->enable();
	$log->set_verbose($verbose_mode);
	my $cmd       = "cleartool desc -fmt \%u vob:$ENV{CLEARCASE_VOB_PN}";
	my $vob_owner = qx ($cmd);
	if ($?) {
		$log->enable(1);
		$log->error("The command: '$cmd' failed\n, command output was $vob_owner\n");
		exit 1;
	}

	$warning = <<ENDWARNING;
Trigger $TRIGGER_NAME prevented operation [$pop_kind]
because an evil twin possibility was detected for the name \n [$element]
Please read the log file for a possible solution.
ENDWARNING

	my $info_1;
	if ( $pop_kind eq "mkelem" ) {

		$info_1 = "The name: [$element] ";

	}
	elsif ( !$pop_kind || $pop_kind =~ /rmname|mkslink/ ) {

		$info_1 = "$info The element name [$element]\n";

	}
	else {

		$log->error("\$ENV{CLEARCASE_POP_KIND} value [$pop_kind] was unexpected");
		exit 1;

	}

	# check if it has been uncatalogued
	chomp( my @lastseen = grep /$pattern$/, keys %uncatalogued );

	my $info_2 = (@lastseen) ? "The name has last been seen in: \n[$uncatalogued{$element}].\n\n" : "";

	$info = <<ENDINFO;
$info_1 
ALREADY exists for the directory:
[$parent]
That name was added in branch version:
[$added{$element}].

$info_2
NOTE:  If you feel you really need to perform this action
please contact the VOB_OWNER ($vob_owner)

ENDINFO

	# Write logfile
	foreach ( split( /\n/, $warning ) ) {
		$log->warning("$_\n");
	}
	$log->information("###########################\n");
	foreach ( split( /\n/, $info ) ) {
		$log->information("$_\n");
	}
	$log->information("###########################\n");

}

sub name_lookup {

	# Parse directory history for the name

	my ( $possible_dupe, $dupver );

	# change to forward slashes in path name
	$pathname =~ tr#\\#/#;

	# Convert any "X:/view_tag/vob_tag/./*" to "X:/view_tag/vob_tag/*"
	$pathname =~ s#\/\.\/#\/#;

	# split element name in dir and leaf
	( $element, $parent ) = fileparse($pathname);
	$parent_dna = "$parent.$sfx";

	# Are we in a snapshot view?
	my $snapview;
	if ( exists( $ENV{'CLEARCASE_VIEW_KIND'} )
		&& $ENV{'CLEARCASE_VIEW_KIND'} ne 'dynamic' )
	{
		$snapview = 1;
	}
	else {

		# The 2nd test is a special case for the vob root.
		$snapview = !-e "$parent$sfx/main" && !-e "$parent/$sfx/main";
	}

	my $found = 0;

	if ($case_sensitive) {
		$pattern = "$element";
	}
	else {
		$pattern = "(?i)$element";
	}

	# Need to escape square brackets, as this string will be used as a regexp.
	$pattern =~ s/\[|\]/\\$&/g;

	$debug_on
	  && $log->information("The Search pattern looks like:\'$pattern\'\n");

	# get lines from lshist that begins with either added or uncat and ends with digit
	my $cmd     = 'cleartool lshist -nop -min -nco -dir -fmt %Nc%Vn\n "' . $parent_dna . '" 2>&1';
	my @history = qx($cmd);

	if ($?) {    # The cleartool lshist failed
		$log->enable(1);
		$log->dump_ccvars;
		$log->error("The command: '$cmd' failed\n");
		$log->error(@history);
		exit 1;
	}
	my @lines =
	  grep { /^added.*?$element.*\\\d+$|^uncat.*?$element.*\\\d+$/i } @history;
	chomp @lines;
	$debug_on && do {
		$log->information("\tThe following lines where selected from the history:\n");
		foreach (@lines) {
			$log->information("\t$_\n");
		}
	};

	%added        = ();    #  table of latest version where NAME was added
	%uncatalogued = ();    #  table of latest version where NAME was seen before uncatalogue

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
			my ( $b, $v ) = ( $branch =~ /(.*)(\d+)$/ );
			$v--;    # decrement version number
			my $lastknown = "$b$v";
			$uncatalogued{$name} = $lastknown unless $uncatalogued{$name};
		}
	}

	$debug_on && do {
		$log->information("\tHere is the \%added hash:\n");
		foreach ( sort keys %added ) {
			$log->information("\t$_ => $added{$_}\n");
		}
	};

	$debug_on && do {
		if ( keys %uncatalogued ) {
			$log->information("\tHere is the \%uncatalogued hash:\n");
			foreach ( sort keys %uncatalogued ) {
				$log->information("\t$_ => $uncatalogued{$_}\n");
			}
		}
	};

	my @match = grep /^$pattern$/, keys %added;
	$found = @match ? $match[$#match] : undef;

}

__END__
