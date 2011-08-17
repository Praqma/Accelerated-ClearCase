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
our $REVISION = "1";
my $verbose_mode = 1;    # Setting the verbose mode to 1 will print the logging information to STDOUT/ERROUT ...even it the log-file isn't enabled
my $debug_on = defined( $ENV{'CLEARCASE_TRIGGER_DEBUG'} ) ? $ENV{'CLEARCASE_TRIGGER_DEBUG'} : undef;

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
----------  ------------   		----------------------------------------------

2011-08-04  Margit Bennetzen	Script created
2011-08-17  Jens Brejner        Praqmatized

------------------------   		----------------------------------------------

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
$log->enable(1);

#Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
$log->set_verbose($verbose_mode);
our $logfile = $log->get_logfile();
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
($logfile) && $log->information($semaphore_status);

# Run this statement to have the trigger dump the CLEARCASE variables
($logfile) && $log->dump_ccvars;

# Main:
# Continue only if operation type is what we are intended for..
if ( lc( $ENV{CLEARCASE_OP_KIND} ) eq "lnname" ) {

    my @result; # Interesting output files
    my $on = 0; # 
    my $parentfolder = dirname( $ENV{CLEARCASE_PN2} );
    my @diffoutput   = `cleartool diff -pre "$parentfolder" 2>&1`;

    foreach (@diffoutput) {
                    if ( $_ =~ /^-------------/ ) {
                ($logfile) && $log->information("Found line containing: [$_]");
                $on = 1;
        if ( $on eq 0 ) {
            if ( $_ =~ /^-------------/ ) {
                ($logfile) && $log->information("Found line containing: [$_]");
                $on = 1;
                push( @result, $_ );
            }
        }
        else {

            $on = 0;
            push( @result, $_ );
        }

    }

    foreach (@result) {

        #use `cleartool chevent -c "added comment" . ` search for filename between | and whitespace
        $log->information($_);
    }
}
__END__

my ( $index, $thislast );
$index = 0;
while ( $index < @diffoutput ) {
 if ( $diffoutput[$index] =~ m/-----\[ renamed to \]-----/i ) {
  ( my $oldname = $diffoutput[ $index + 1 ] ) =~ s/(..)(.*)(.\s+--\d+.*)/$2/;
  ( my $newname = $diffoutput[ $index + 3 ] ) =~ s/(..)(.*)(.\s+--\d+.*)/$2/;
  print "Element [$newname] previously named [$oldname]\n";
  $index = $index + 4;
  next;
 }
 elsif ( $diffoutput[$index] =~ m/-----\[ added \]-----/i ) {
  ( my $addedname = $diffoutput[ $index + 1 ] ) =~ s/(..)(.*)(.\s+--\d+.*)/$2/;
  print "New Element [$addedname]\n";
  $index = $index + 2;
  next;
 }
 else {

  # print "\$index is $index  in $diffoutput[$index]\n ";
  $index++;
 }
}

	
