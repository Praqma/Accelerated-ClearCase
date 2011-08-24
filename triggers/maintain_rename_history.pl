require 5.000;
use strict;

#Getting the script dir
our ( $Scriptdir, $Scriptfile );

BEGIN {
  use File::Basename;
  ( $Scriptfile, $Scriptdir ) = fileparse($0);
}
use File::Basename;
use lib $Scriptdir. "..";
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
our $REVISION = "3";
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
# Continue only if operation type is what we are intended for..
if ( lc( $ENV{CLEARCASE_OP_KIND} ) eq "lnname" ) {
  $log->information("Fired for Clearcase operation $ENV{CLEARCASE_OP_KIND}") if ($debug_on);
  my $parentfolder = dirname( $ENV{CLEARCASE_PN} );
  my $cmd          = "cleartool diff -ser -pre \"$parentfolder\" 2>&1";
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
      &update_event( 'comment' => "$comment", 'object' => $parentfolder );
      &update_event( 'comment' => "$comment", 'object' => "$ENV{CLEARCASE_PN}$ENV{CLEARCASE_XN_SFX}" );

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
else {
  $log->information("Fired for Clearcase operation $ENV{CLEARCASE_OP_KIND}");
}

sub update_event () {

  # update object event
  my %parms = @_;
  $log->information("Called sub update_event with [comment] = [$parms{'comment'}] and [object] = $parms{'object'}") if ($debug_on);
  my @reply = qx(cleartool chevent -append -c \"$parms{'comment'}\" "$parms{'object'}" 2>&1);
  $log->warning( "Trouble appending comment: " . join(@reply) ) if ($?);
  $log->information("$parms{'comment'}") if ($debug_on);
}

__END__

