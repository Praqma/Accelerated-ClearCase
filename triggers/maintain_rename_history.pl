require 5.000;
use strict;

#Getting the script dir
our ( $Scriptdir, $Scriptfile );

BEGIN {
	use File::Basename;
	( $Scriptfile, $Scriptdir ) = fileparse($0);
}

use File::Basename;
use lib $Scriptdir . "../";
use praqma::scriptlog;
use praqma::trigger_helper;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME   = "ACC_RENAME_HISTORY";
our %install_params = (
	"name"     => $TRIGGER_NAME,                     # The name og the trigger
	"mktrtype" => "-postop lnname -element -all",    # The stripped-down mktrtype command
	"supports" => "bccvob,ucmvob",                   # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "0.1";
our $REVISION = "4";
my $debug_on = defined( $ENV{'CLEARCASE_TRIGGER_DEBUG'} ) ? $ENV{'CLEARCASE_TRIGGER_DEBUG'} : 0;

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as ClearCase trigger script for the
#     $TRIGGER_NAME trigger.
#
#     The trigger maintains rename history to renamed elements and parent folder
#
#     This script supports self-install (execute with the -install
#     switch to learn more).
#
#     Read the POD documentation in the script for more details
#     Date:       2011-08-04
#     Author:     Jens Brejner, jbr\@praqma.net
#     Copyright:  Praqma A/S
#     License:    GNU General Public License v3.0
#     Support:    http://launchpad.net/acc
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         		NOTE
----------  -----------------   -------------------------------------------
2012-01-30  Jens Brejner        Support for move between directories (v 0.1.4)
2011-08-24  Jens Brejner        Fixed bug on write to element (v 0.1.3)
2011-08-17  Jens Brejner        Praqmatized (v 0.1.2)
2011-08-04  Margit Bennetzen    Script created (v 0.1.1)

-----------------------------  ----------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options

$thelp->require_trigger_context;

# Look for semaphore for trigger cancelling.
our $semaphore_status = $thelp->enable_semaphore_backdoor();

# Initiate logging.
our $log = scriptlog->new;

#Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->conditional_enable();

#Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
$log->set_verbose();
our $logfile = $log->get_logfile();
if ($logfile) {
	$debug_on = 1;
	$log->set_verbose($debug_on);
}
$log->information("logfile is: $logfile\n") if ($debug_on);
$log->information($semaphore_status)        if ($debug_on);
$log->dump_ccvars()                         if ($debug_on);

# Main:
my ( $targetfolder, $sourcefolder );

# Continue only if operation type is what we are intended for..
if ( lc( $ENV{CLEARCASE_OP_KIND} ) eq "lnname" ) {
	$log->information("Fired for Clearcase operation $ENV{CLEARCASE_OP_KIND}") if ($debug_on);
	$targetfolder = dirname( $ENV{CLEARCASE_PN} );
	$sourcefolder = dirname( $ENV{CLEARCASE_PN2} );
	$log->information("\$targetfolder has value [$targetfolder], \$sourcefolder has value [$sourcefolder]") if ($debug_on);

	if ( $targetfolder eq $sourcefolder ) {
		$log->information("Rename in same folder, running sub elementrenamed") if ($debug_on);
		elementrenamed();
	}
	else {
		$log->information("Element moved to different folder, running sub elementmoved") if ($debug_on);
		elementmoved();
	}
}
else {

	$log->enable(1);
	$log->assertion_failed("Fired for Clearcase operation $ENV{CLEARCASE_OP_KIND}");
}

###############################################################################

sub unqualifypath {

	# remove drive and view part of a pathname
	#
	my %parms = @_;
	$log->assertion_failed("Failed unqualifying path") unless ( $parms{'fullpath'} =~ m/$ENV{CLEARCASE_VIEW_TAG}/ );

	( my $unqualifiedpath = $parms{'fullpath'} ) =~ s/(.*$ENV{CLEARCASE_VIEW_TAG})(.*)/$2/;
	$log->information("\$unqualifiedpath is now $unqualifiedpath, taken from $parms{'fullpath'}") if ($debug_on);
	my ( $filename, $directory ) = fileparse($unqualifiedpath);
	chop $directory;    # chop trailing path sep.
	$log->information("\$directory is [$directory] , \$filename is [$filename]") if ($debug_on);
	return ( $directory, $filename );
}

sub elementmoved {

	$log->information("Is in elementmoved sub") if ($debug_on);
	my $comment;
	my ( $old_dir, $old_element ) = unqualifypath( 'fullpath' => $ENV{CLEARCASE_PN2} );
	my ( $new_dir, $new_element ) = unqualifypath( 'fullpath' => $ENV{CLEARCASE_PN} );

	# Update info on version of sourcefolder
	$comment = "Element [$old_element] moved to [$new_dir] as [$new_element]";
	update_event( 'comment' => "$comment", 'object' => "$sourcefolder" );

	# Update info on version of targetfolder
	$comment = "Element [$new_element] moved from [$old_dir] (was named [$old_element])";
	update_event( 'comment' => "$comment", 'object' => "$targetfolder" );

	# Update info on element that was moved
	$comment = "Element moved from [$old_dir] to [$new_dir]";
	update_event( 'comment' => "$comment", 'object' => "$ENV{CLEARCASE_PN}$ENV{CLEARCASE_XN_SFX}" );

}

sub elementrenamed {

	my $cmd = "cleartool diff -ser -pre \"$targetfolder\" 2>&1";
	$log->information("Diffcommand is [$cmd]") if ($debug_on);
	my @diffoutput = qx($cmd);
	$log->information( "\@diffoutput contains " . scalar(@diffoutput) . " lines: " . join(@diffoutput) ) if ($debug_on);
	my ( $action, $index );
	$index = 0;

	while ( $index < @diffoutput ) {
		$_ = $diffoutput[$index];

		# look for pattern like this '-----[ renamed to ]-----'
		if (/^(-{5}\[\s)(.*)(\s\]-{5})/) {
			$action = $2;
		}
		else {
			$index++;
			next;
		}

		if ( $action =~ /renamed to/i ) {

			# Work on block of 4 lines, which describes the rename operation
			if ($logfile) {
				$log->information("Found rename pattern starting at line $index of diffoutput:");
				foreach ( $diffoutput[ $index .. ( $index + 3 ) ] ) {
					$log->information("\t$_");
				}
			}

			# Extract element names
			( my $oldname = $diffoutput[ $index + 1 ] ) =~ s/(^..)(.*)(.\s+--\d+.*$)/$2/;
			( my $newname = $diffoutput[ $index + 3 ] ) =~ s/(^..)(.*)(.\s+--\d+.*$)/$2/;
			chomp $oldname;
			chomp $newname;
			my $comment = "Element [$newname] previously named [$oldname]";
			update_event( 'comment' => "$comment", 'object' => $targetfolder );
			update_event( 'comment' => "$comment", 'object' => "$ENV{CLEARCASE_PN}$ENV{CLEARCASE_XN_SFX}" );

			# Move forward to next interesting block
			$index = $index + 4;
			next;
		}
		else {

			# Move forward to next interesting block
			$log->information("Found line $_ - moving on...") if ($debug_on);
			$index = $index + 2;
			next;
		}
	}
}

sub update_event () {

	# update object event
	my %parms = @_;
	$log->information("Called sub update_event with [comment] = [$parms{'comment'}] and [object] = $parms{'object'}") if ($debug_on);
	my $cmd = "cleartool chevent -append -c \"$parms{'comment'}\" \"$parms{'object'}\" 2>&1";
	$log->information("Will call [$cmd]") if ($debug_on);
	my @reply = qx($cmd);
	$log->warning( "Trouble appending comment: " . join(@reply) ) if ($?);
	$log->information("$parms{'comment'}") if ($debug_on);
}

__END__

