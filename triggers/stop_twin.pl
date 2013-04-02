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
our $TRIGGER_NAME   = "ACC_STOP_TWIN";
our %install_params = (
	"name"     => $TRIGGER_NAME,                    # The name og the trigger
	"mktrtype" => "-preop lnname -element -all",    # The stripped-down mktrtype command
	"supports" => "bccvob,ucmvob",                  # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "1.0";
our $REVISION = "36";
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
----------  ------------   ----------------------------------------------
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
2011-06-07  Jens Brejner   Implement Automatic merge to fix evil twin (v1.0.33)
2011-10-11  Jens Brejner   Updated documentation, minor beautification (v1.0.34)
2012-03-15  Jens Brejner   Remove full automerge - it is too unpredictable (v1.0.35)
2013-03-18  Jes Struck     Changed messages when automerge is of  (v1.0.36)
------------------------   ----------------------------------------------

ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;

# Look for semaphore, respecting a local semaphore path via env. var.
our $semaphore_status = $thelp->enable_semaphore_backdoor( $ENV{'CLEARCASE_USE_LOCAL_SEMAPHORE'} );

# Initiate logging.
our $log = scriptlog->new;

#Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->conditional_enable();

#Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
$log->set_verbose();
our $logfile = $log->get_logfile();
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
($logfile) && $log->information($semaphore_status);
($logfile) && $log->dump_ccvars;                              # Run this statement to have the trigger dump the CLEARCASE variables

# Script scope variables
my (
	%twincfg, $case_sensitive, $viewkind, $pathname, $sfx,          $pop_kind, $user, $parent,
	$element, $parent_dna,     $pattern,  %added,    %uncatalogued, $found,    $info, $warning,
);

# Read optional local configuration of trigger
$thelp->get_config( \%twincfg );
$case_sensitive = $twincfg{CaseSensitive};
$viewkind       = $ENV{CLEARCASE_VIEW_KIND};
$pathname       = $ENV{CLEARCASE_XPN};
$sfx            = $ENV{CLEARCASE_XN_SFX} ? $ENV{CLEARCASE_XN_SFX} : '@@';
$user           = $ENV{CLEARCASE_USER};
$pop_kind       = lc( $ENV{CLEARCASE_POP_KIND} );

# Main:
# Continue only if operation type is what we are intended for..
if ( lc( $ENV{CLEARCASE_OP_KIND} ) eq "lnname" ) {
	chdir $ENV{SYSTEMDRIVE};

	# Search history for "name"
	name_lookup();
	if ($found) {

		# Found evil twin, determine what to do about that
		$log->enable(1);
		$log->set_verbose(1);
		$logfile = $log->get_logfile();

		unless ( $twincfg{AutoMerge} eq 0 || $twincfg{AutoMerge} eq 1 ) {
			$log->assertion_failed("Value [$twincfg{AutoMerge}] is not a valid value for automerge options");
		}
		print_no_merge_msg();
		if ( $twincfg{AutoMerge} eq 0 ) {
			my @reply = qx(cleartool diff -predecessor \"$parent\" 2>&1);
			unless ($?) {

				# "cleartool diff" returns 0 if versions are identical
				$log->information("Undoing checkout of [$parent] because there are no changes") if ($debug_on);
				qx(cleartool uncheckout -rm \"$parent\");
			}
			exit 1;
		}

		# Script default is overwritten, they want us to try to fix during script execution
		# Write batch files to fix the situation

		if ( $twincfg{AutoMerge} eq 1 ) {
			my $fixcommand = build_fixcommands();

			# Merge that name back for the user
			runcmd( 'cmd' => "call \"$fixcommand\"" );
			$log->information("Evil twin detected.\n");
			$log->information("We have tried to get around it, but haven't checked in the changes, please verify the result");
			$log->information("- and check in if you are satisfied");
			exit 1;
		}
	}
	else {

		# No duplicate element is found on invisible branches
		# Allow the creation of the element.
		if ($debug_on) {
			$log->information("Value of \$found is now [$found]");
			$log->information("Found no twins");
		}

		exit 0;
	}

	# Prevent the operation anyway - as we should never end here
	exit 1;
}    # End if ( lc( $ENV{'CLEARCASE_OP_KIND'} ) eq "lnname" )

$log->assertion_failed("Script ran out of context");

############################## SUBS BELOW  ####################################

sub runcmd {
	my %args = (@_);
	$log->assertion_failed("A command is required") unless exists $args{'cmd'};
	my $command = $args{'cmd'} . ' 2>&1';
	my @retval  = qx($command);
	if ($?) {
		$log->assertion_failed( "The command [$args{'cmd'}] exited with " . scalar($?) / 256 . " :\n" . join( '', @retval ) );
	}
	return @retval;
}

sub build_fixcommands {

	my ( $fixcmd, $tmpfilename, $foundpath, @mkmerge, @mkci, $version, $win32parent, $win32foundpath, $win32element, $mergeoptions );

	$mergeoptions = "-graphical";
	$version      = $added{$element};

	$tmpfilename = time();
	$foundpath   = $parent_dna . $version;
	( $win32parent    = $parent )    =~ tr#/#\\#;
	( $win32foundpath = $foundpath ) =~ tr#/#\\#;
	( $win32element   = $element )   =~ tr#/#\\#;
	my $winsource = $twincfg{AutoMerge} eq 0 ? "$win32element " : "$win32element.mkelem ";

	@mkmerge = ( <<"END_OF_MKMERGE" =~ m/^\s*(.+)/gm );
REM The proper way to correct the situation, is to re-introduce the name
REM $win32element in the directory by executing the following commands in order:
REM BATCH START

pushd  "$win32parent"
rename "$winsource " $tmpfilename
cleartool co -c "Re-introducing the name $element from $version" .
cleartool merge $mergeoptions -c "Re-introducing the name $element" -to . "$win32foundpath"
cleartool co -nc "$win32element"
copy /y $tmpfilename "$win32element"

END_OF_MKMERGE

	# Write commands to batch file
	my $fixbat = $parent . "fix_evil_twin_of_" . $element . "_" . $tmpfilename . ".bat";
	open( AUTOBAT, " > $fixbat" ) or die "Couldn't open $fixbat for writing : $!";
	foreach (@mkmerge) {
		print AUTOBAT "$_\n";
	}
	print AUTOBAT "exit\n";
	close AUTOBAT;
	return $fixbat;
}

sub print_no_merge_msg {
	my $cmd       = "cleartool desc -fmt \%u vob:$ENV{CLEARCASE_VOB_PN}";
	my $vob_owner = qx ($cmd);
	if ($?) {
		$log->error("The command : '$cmd' failed \n, command output was $vob_owner\n");
		exit 1;
	}
	my $info_1;
	if ( $pop_kind eq "mkelem" ) {
		$info_1 = "The file name : [$element]";
	}
	elsif ( !$pop_kind || $pop_kind =~ /rmname|mkslink/ ) {
		$info_1 = "The element name [$element] \n";
	}
	else {
		$log->assertion_failed("\$ENV{CLEARCASE_POP_KIND} value [$pop_kind] was unexpected");
		exit 1;
	}

	# check if it has been uncatalogued
	chomp( my @lastseen = grep /$pattern$/, keys %uncatalogued );

	# split branch and version
	my ( $branch, $version ) = ( $uncatalogued{$element} =~ /(.*)(\d+)$/ );
	$version--;    # decrement version number
	my $info_2 = (@lastseen) ? "The name has last been seen in :\n[$branch$version].\n\n" : "";
	$info = $info_1 . "\nwas previously used in this directory.";
	if ( $twincfg{AutoMerge} eq 0 ) {
		$info = $info . "\n\nNOTE:  If you feel you really need to perform this action\nplease contact the ClearCase support";
	}

	# Write logfile
	$log->information("$info\n###########################");
}

sub name_lookup {

	# Parse directory history for the name
	my ( $possible_dupe, $dupver, @lines );
	%added        = ();    #  table of latest version where NAME was added
	%uncatalogued = ();    #  table of latest version where NAME was seen before uncatalogue

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

	# Need to escape square brackets and paranthesis , as this string will be used as a regexp.
	$pattern = "$element";
	$pattern =~ s/\(|\)|\[|\]/\\$&/g;

	unless ($case_sensitive) {
		$pattern = "(?i)" . $pattern;
	}

	$log->information("The Search pattern looks like: [$pattern]") if ($debug_on);

	# get lines from lshist that begins with either added or uncat and ends with digit
	my $cmd = 'cleartool lshist -nop -min -nco -dir -fmt %Nc%Vn\n "' . $parent_dna . '"';
	$log->information("\t\$cmd is [$cmd]") if ($debug_on);
	my @history = runcmd( 'cmd' => "$cmd" );
	if ($debug_on) {
		$log->information( "\tHere comes the history listing:\n\t" . join( '', @history ) );

	}
	foreach (@history) {
		chomp;
		$_ =~ s/^\s+//;

		if ( index( $_, $element ) == -1 ) {
			$log->information("Skipping line [$_]") if ($debug_on);
			next;
		}

		# isolate elementname and branch version
		my ( $action, $name, $junk, $branch ) = /(.*")(.*)("\.)(.*)/;
		$log->information("Line [$_] was split into: \$action=[$action], \$name=[$name], \$junk=[$junk] and \$branch=[$branch]") if ($debug_on);

		# Fill table of latest version where file was added
		if (/^Added/i) {
			$added{$name} = $branch unless $added{$name};
			next;
		}

		# Fill table of latest version where NAME was uncatalogued
		if (/^Uncat/i) {
			$uncatalogued{$name} = $branch unless $uncatalogued{$name};
			next;
		}
	}
	if ($debug_on) {
		$log->information("\tHere is the \%added hash:\n");
		foreach ( sort keys %added ) {
			$log->information("\t$_ => $added{$_}\n");
		}
		if ( keys %uncatalogued ) {
			$log->information("\tHere is the \%uncatalogued hash:\n");
			foreach ( sort keys %uncatalogued ) {
				$log->information("\t$_ => $uncatalogued{$_}\n");
			}
		}
		else {
			$log->information("\tNo keys in \%uncatalogued hash:\n");
		}
	}
	my @match = grep { /^$pattern$/ } keys %added;
	if ($debug_on) { $log->information( "Found " . scalar(@match) . " matching keys" ); }
	$found = (@match) ? scalar(@match) : undef;
	if ($debug_on) { $log->information("Value of \$found is now [$found]"); }
}
__END__
