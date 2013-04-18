require 5.000;
use strict;

our ( $Scriptdir, $Scriptfile, $parentdir );

BEGIN {
    use File::Basename;
    $Scriptdir  = dirname(__FILE__) . "\\";
    $Scriptfile = basename(__FILE__);

    # Ensure that the view-private file will get named back on rejection.
    END {
        rename( "$ENV{CLEARCASE_PN}.mkelem", $ENV{CLEARCASE_PN} )
          if $? && !-e $ENV{CLEARCASE_PN} && -e "$ENV{CLEARCASE_PN}.mkelem";

    }
}

use lib $Scriptdir . "..\\";

use praqma::scriptlog;
use praqma::trigger_helper;

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
our $REVISION = "8";

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
2013-04-18  Jens Brejner       Proper undo checkout of parent - or checkin (v 0.1.8)
2013-04-17  Jens Brejner       Fix failing check on extension (v 0.1.7)
2013-04-17  Jens Brejner       Fix missing variable definition  (v 0.1.6)
2012-12-04  Jens Brejner       Reintroduce check for files without extension (v 0.1.5)
2012-10-25  Jens Brejner       Improve clarity of message (v 0.1.4)
2012-06-19  Jens Brejner       One message only before exit (v 0.1.3)
2012-02-16  Jens Brejner       No abbreviation in cleartool command (v 0.1.2)
2011-11-01  Margit Bennetzen   Script rename to pre_lnname and whitespacecheck added (v0.2)
2011-09-27  Margit Bennetzen   Script added to acc (v0.1)
------------------------------------------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;
our $semaphore_status = $thelp->enable_semaphore_backdoor;

# Script scope variables
my %trgconfig;

# Enable external configuration options
$thelp->get_config( \%trgconfig );

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

# Only process if proper OP_KIND
if ( $ENV{CLEARCASE_OP_KIND} eq "lnname" ) {

    # Require file element has extension if enabled from configuration file
    # The check for if element is file is differenct depending on whether we are adding to source control or renaming
    if ( $trgconfig{require_extension} ) {
        if ( $ENV{CLEARCASE_POP_KIND} eq 'mkelem' && -f "$ENV{CLEARCASE_PN}.mkelem" ) {

            # While creating a new element it renamed temporarily to *.mkelem
            $log->information("Element being added, check for extension");
            check_extension();
        }
        if ( $ENV{CLEARCASE_POP_KIND} eq 'rmname' && $ENV{CLEARCASE_MTYPE} eq 'file element' ) {

            # Element being renamed and element type is detectable
            $log->information("Element being renamed, check for extension");
            check_extension();
        }
        final_exit();
    }

    # Check pathlength if requested
    if ( $trgconfig{pathlength} > 0 && $ENV{CLEARCASE_POP_KIND} eq 'mkelem' ) {
        my $pathlength = length( $ENV{CLEARCASE_PN} );
        if ( $pathlength > $trgconfig{pathlength} ) {
            $log->error("The length of [$ENV{CLEARCASE_PN}] is $pathlength, which exceeds $trgconfig{pathlength}. Use a shorter name.");
            $log->error("The path length limitation of $trgconfig{pathlength}, has been chosen by ClearCase Administrator.");
            final_exit();
        }
        else {
            $log->information("Length of [$ENV{CLEARCASE_XPN}] is OK; $pathlength is less than $trgconfig{pathlength}");
        }
    }

    # Check for whitespaces
    if ( $trgconfig{whitespacecheck} && $ENV{CLEARCASE_POP_KIND} eq 'mkelem' ) {
        my $reason;
        my ( $name, $extension ) = ( fileparse( $ENV{CLEARCASE_PN}, qr/\.[^.]*/ ) )[ 0, 2 ];
        my $filename = $name . $extension;

        # Double whitespace anywhere ?
        $reason = "contains consecutive whitespaces";
        complain( reason => $reason, file => $filename, part => $name )      if ( $name      =~ m/\s{2,}/g );
        complain( reason => $reason, file => $filename, part => $extension ) if ( $extension =~ m/\s{2,}/g );

        # Starts with whitespace ?
        $reason = "begins with whitespace";
        complain( reason => $reason, file => $filename, part => $name )      if ( $name      =~ m/^\s+.*/g );
        complain( reason => $reason, file => $filename, part => $extension ) if ( $extension =~ m/^\.\s+.*/g );

        # Ends with whitespace ?
        $reason = "ends with whitespace";
        complain( reason => $reason, file => $filename, part => $name )      if ( $name      =~ m/.*\s+$/g );
        complain( reason => $reason, file => $filename, part => $extension ) if ( $extension =~ m/.*\s+$/g );

        final_exit();

    }

    # Exit clean, found nothing to stop the operation
    exit 0;
}

die "Trigger called out of context, we should never end here.";

############################## S U B S ########################################

sub check_extension {
    my $file = basename( $ENV{CLEARCASE_PN} );
    $log->information("Check for extension on file [$file]");

    # Match a dot followed by any number of non dots at the end of the line
    if ( $file =~ /(\.[^.]+)$/ ) {
        $log->information("File [$file] has an extension");
    }
    else {
        $log->error("File [$file] has no extension, please rename so it has an extension\n");
    }

}

sub final_exit {

    # Cleanup
    my $exitcode = $log->get_accumulated_errorlevel();

    if ( $exitcode eq 2 ) {
        $parentdir = dirname( $ENV{CLEARCASE_PN} );

        # is parentdir checked-out ?
        if ( -w $parentdir ) {
            $log->information("[$parentdir] is writeable (checkedout)");
            my @reply = qx(cleartool diff -predecessor \"$parentdir\" 2>&1);
            unless ($?) {

                # "cleartool diff" returns 0 if versions are identical
                $log->information("Undoing checkout of [$parentdir] because there are no changes");
                qx(cleartool uncheckout -rm \"$parentdir\");
            }
            else {

                # "cleartool diff" returned 1, so there are changeds - check it in
                $log->information("[$parentdir] is being checked in");
                qx(cleartool checkin -ncomment \"$parentdir\");
            }
        }
    }
    $log->information("The script Exit Code is : $exitcode");
    exit $exitcode;

}

sub complain {

    my %parms    = @_;
    my $reason   = $parms{reason};
    my $filename = $parms{file};
    my $part     = $parms{part};

    my $msg = "\nThe filename: \"$filename\"\nis forbidden, because the part: \"$part\"\n\n$reason";

    if ( defined( $ENV{CLEARCASE_CMDLINE} ) || defined( $ENV{ATRIA_WEB_GUI} ) ) {
        $log->error($msg);
    }
    else {

        $log->enable(1);
        $log->set_verbose();
        $log->error($msg);
        $msg =~ s/\"/\"\"/g;
        my $cmd = 'clearprompt proceed -type error -default proceed -prompt "' . $msg . '" -newline -mask proceed';

        # On windows 7 (32 bit, Enterprise edition, it seems it is not nessecary to call clearprompt
        # my $ret = qx($cmd);
    }
}

__END__
