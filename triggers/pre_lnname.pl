require 5.000;
use strict;

our ( $Scriptdir, $Scriptfile );

BEGIN {
	use File::Basename;
	$Scriptdir  = dirname(__FILE__) . "\\";
	$Scriptfile = basename(__FILE__);

}

use lib $Scriptdir . "..\\";

use scriptlog;
use trigger_helper;
use File::Basename;

$| = 1;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME = "ACC_PRE_LNNAME";

our %install_params = (
	"name"     => $TRIGGER_NAME,                     # The name of the trigger
	"mktrtype" => "-element -all -preop lnname ",    # The stripped-down mktrtype command
	"supports" => "bccvob,ucmvob",                   # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "0.1";
our $REVISION = "1";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as trigger script for the
#     $TRIGGER_NAME trigger.
#     The trigger runs before rmname on an element
#     The user cannot rmname if the file is checked out.
#     This script supports self-install (execute with the -install
#     switch to learn more).
#     Read the POD documentation for more details
#     Date:       2011-27-09
#     Author:
#     Copyright:  Praqma A/S
#     License:    GNU General Pulic License v3.0
#     Support:    http://launchpad.net/acc
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR             NOTE
----------  -----------------  ---------------------------------------------------
2011-09-27  Margit Bennetzen   Script added to acc (v0.1)
2011-11-01  Margit Bennetzen   Script rename to pre_lnname and whitespacecheck added (v0.2)
------------------------------------------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;
our $semaphore_status = $thelp->enable_semaphore_backdoor;

# Script scope variables
my ( %trgconfig, $filename );

# Enable external configuration options
$thelp->get_config( \%trgconfig );

$filename = basename( $ENV{CLEARCASE_XPN} );

#Enable the features in scriptlog

our $log = scriptlog->new();
$log->set_verbose();

#Define either environment variable CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->conditional_enable();

my $logfile = $log->get_logfile;
($logfile)
  && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
($logfile) && $log->information($semaphore_status);
($logfile)
  && $log->dump_ccvars;                              # Run this statement to have the trigger dump the CLEARCASE variables

########################### MAIN ###########################
# Vob symbolic links can not be renamed.
exit 0 if -l $ENV{CLEARCASE_PN};

# Only process if proper OP_KIND
if ( $ENV{CLEARCASE_OP_KIND} eq "lnname" ) {

	# Check pathlength if requested
	if ( $trgconfig{pathlength} > 0 ) {

		if ( length( $ENV{CLEARCASE_XPN} > $trgconfig{pathlength} ) ) {
			$log->error( "The length of [$ENV{CLEARCASE_XPN}] exceeds $trgconfig{pathlength}, so it is not allowed. Use a shorter name." );
		}
		else {
			$log->information("Length is ok");
		}
	}



	# Check for whitespaces
	if ( $trgconfig{whitespacecheck} ) {

		#this expression searches for leading and trailing spaces and empty strings
		if ( $filename =~ m/^\s+.*|.*\s+$|^\s+$/ ) {
# TODO Can you tell where the white space was found ?

			$log->error("Filename $filename contains bad whitespaces");
		}
## TODO Maybe code like this instead of the if below
#my @parts = split(/\./, $filename);
## Part before last dot
#if ($parts[( $#parts -1 )] =~ /.*\s+$/) print "Disallowed whitespace detected in [$parts[($#parts-1)].]";
## Part after last dot
#if ($parts[$#parts] =~ /^\s+.*/) print "Disallowed whitespace detected in [.$parts[$#parts]]";
#

		# finds the extension and checks for whitespaces around the last dot
		if ( $filename =~ m/.*(\..)/s ) {
			my $sub = substr $filename, ( index( $filename, $1 ) - 2 );
			if ( $sub =~ (m/\s\.|\.\s/) ) {
				$log->error("Filename $filename contains bad whitespaces");
			}

		}
	}

	exit $log->get_accumulated_errorlevel();

}
die "trigger called out of context, we should never end here.";

__END__

