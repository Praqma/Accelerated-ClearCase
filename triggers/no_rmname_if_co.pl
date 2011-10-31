require 5.000;
use strict;

our ( $Scriptdir, $Scriptfile );

BEGIN {
  use File::Basename;
  $Scriptdir  = dirname(__FILE__) . "\\";
  $Scriptfile = basename(__FILE__);

}

use lib $Scriptdir . "..\\";

use praqma::scriptlog;
use praqma::trigger_helper;
use File::Basename;

$| = 1;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME = "ACC_BLOCK_RMNAME_IF_CO";

our %install_params = (
  "name"     => $TRIGGER_NAME,                     # The name og the trigger
  "mktrtype" => "-element -all -preop rmname ",    # The stripped-down mktrtype command
  "supports" => "bccvob,ucmvob",                   # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "0.1";
our $REVISION = "4";

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
#     Date:       2011-04-05
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
2011-04-26  Jens Brejner       Add external config so parent folder can be considered.
2011-04-05  Margit Bennetzen   Script added to acc (v0.1)
------------------------------------------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;
our $semaphore_status = $thelp->enable_semaphore_backdoor;

# Enable external configuration options
my %twincfg;
$thelp->get_config( \%twincfg );

#Enable the features in scriptlog

our $log = scriptlog->new();
$log->set_verbose();

#Define either environment variable CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->conditional_enable();

my $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
($logfile) && $log->information($semaphore_status);
($logfile) && $log->dump_ccvars;                              # Run this statement to have the trigger dump the CLEARCASE variables

########################### MAIN ###########################
# Vob symbolic links can not be renamed.
exit 0 if -l $ENV{CLEARCASE_PN};

my ( $msg, $msgvar, $element );

# Only process if proper OP_KIND
if ( $ENV{CLEARCASE_OP_KIND} eq "rmname" ) {

  if ( $twincfg{AlsoParent} ) {
    $element = dirname( $ENV{CLEARCASE_PN} );
    $msgvar  = "'s parent folder";
    ($logfile) && $log->information("Looking for checkouts of parent directory called [$element]");
    if ( check_co() ) {
      exit 1;
    }
  }

  $element = $ENV{CLEARCASE_PN};
  $msgvar  = " is";
  ($logfile) && $log->information("Calling after Alsoparent, Element is [$element]");
  if ( check_co() ) {
    exit 1;

  }
  exit 0;
}

#
die "trigger called out of context, we should never end here.";

########################### SUBS ###########################
sub check_co {

  # Returns 0 if there are no (dangerous) checkouts
  # Returns 1 if there are dangerous checkouts

  my $retval = 0;
  my $cmd    = "cleartool lscheckout -directory -fmt \"\%Tf,\%u\\n\" \"$element\"";
  ($logfile) && $log->information("Command looking for checkouts : [$cmd]");

  $msg = "ERROR...\nYou cannot rename the element [$element] while it$msgvar is checked out by ";

  # Get view and user pairs for checkouts of element
  my @co_info = qx($cmd);

  ($logfile) && $log->information( "Clearcase replies: \n\t" . join( '\t', @co_info ) );
  if (@co_info) {
    ($logfile) && $log->information("There ARE checkouts");
    foreach (@co_info) {

      ($logfile) && $log->information("There is a checkout in $_");
      chomp($_);
      my ( $view, $user ) = split( /,/, $_ );
      if ( ( $twincfg{AlsoParent} ) && ( $view eq $ENV{CLEARCASE_VIEW_TAG} ) ) {

        # In current view, parent dir must be checked out for rename to succeed, so we accept that
        ($logfile) && $log->information("Ignoring co of parent dir, it is this view");
        next;
      }

      ($logfile) && $log->information("Found view $view and user $user ");

      $msg .= "$user in view $view";
      $log->enable(1);
      $log->set_verbose(1);

      $log->information($msg);
      ++$retval;
    }
  }
  else {
    ($logfile) && $log->information("scalar \@co_info is ... not ? ");
  }
  return $retval;
}

__END__

