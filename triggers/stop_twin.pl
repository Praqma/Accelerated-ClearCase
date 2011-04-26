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
our $REVISION = "32";

my $verbose_mode = 0;    # Setting the verbose mode to 1 will print the logging information to STDOUT/ERROUT ...even it the log-file isn't enabled
my $debug_on =
  defined( $ENV{'CLEARCASE_TRIGGER_DEBUG'} )
  ? $ENV{'CLEARCASE_TRIGGER_DEBUG'}
  : undef;

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
my %twincfg;
$thelp->get_config( \%twincfg );

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable();    #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose;             #Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
our $logfile = $log->get_logfile;
($logfile)
  && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
($logfile) && $log->information($semaphore_status);
($logfile)
  && $log->dump_ccvars;                              # Run this statement to have the trigger dump the CLEARCASE variables

if ( lc( $ENV{'CLEARCASE_OP_KIND'} ) eq "lnname" ) { # continue only if operation type is what we are intended for..

    # Here starts the actual trigger code.

    my $case_sensitive = $twincfg{CaseSensitive};
    my ( $possible_dupe, $dupver );
    my $viewkind = $ENV{'CLEARCASE_VIEW_KIND'};
    my $pathname = $ENV{'CLEARCASE_XPN'};
    my $sfx      = $ENV{'CLEARCASE_XN_SFX'} ? $ENV{'CLEARCASE_XN_SFX'} : '@@';

    # change to forward slashes in path name
    $pathname =~ tr#\\#/#;

    # Convert any "X:/view_tag/vob_tag/./*" to "X:/view_tag/vob_tag/*"
    $pathname =~ s#\/\.\/#\/#;

    # split element name in dir and leaf
    my ( $element, $parent ) = fileparse($pathname);
    my $parent_dna = "$parent.$sfx";

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
    my $pattern;    # Casesensitive search pattern - or not

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
    my %added        = ();    #  table of latest version where NAME was added
    my %uncatalogued = ();    #  table of latest version where NAME was seen before uncatalogue

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

    # No duplicate element is found on invisible branches
    # Allow the creation of the element.
    exit 0 unless $found;

    $log->enable();
    $log->set_verbose($verbose_mode);
    my $user     = "$ENV{'CLEARCASE_USER'}";
    my $pop_kind = "$ENV{'CLEARCASE_POP_KIND'}";
    $cmd = "cleartool desc -fmt \%u vob:$ENV{'CLEARCASE_VOB_PN'}";
    my $vob_owner = `$cmd`;

    if ($?) {
        $log->enable(1);
        $log->error("The command: '$cmd' failed\n, command output was $vob_owner\n");
        exit 1;
    }

    my ( $warning, $info );

    $warning = " Trigger $TRIGGER_NAME prevented operation [$pop_kind]\n";
    $warning = "$warning because an evil twin possibility was detected for the name \n [$element] \n";
    $warning = "$warning Please read the log file for a possible solution. \n";

    if ( $pop_kind eq "mkelem" ) {

        # From a mkelem command
        $info = "$info The name: [$element]\n";

    }
    else {

        # From a "ln", "ln -s" or "mv" command
        if (   !$pop_kind
            || ( $pop_kind eq "rmname" )
            || ( $pop_kind eq "mkslink" ) )
        {

            $info = "$info The element name [$element]\n";

        }
    }

    $info = "$info ALREADY exists for the directory:\n [$parent]\n";
    $info = "$info That name was added in branch version:\n";
    $info = "$info [$added{$element}].\n";
    $info = "$info \n";

    # check if it has been uncatogued
    chomp( my @lastseen = grep /$pattern$/, keys %uncatalogued );

    if (@lastseen) {
        $info = "$info The name has last been seen in: \n";
        $info = "$info [$uncatalogued{$element}].\n";
        $info = "$info \n";
    }

    $info = "$info NOTE:  If you feel you really need to perform this action\n";
    $info = "$info e-mail the VOB_OWNER ($vob_owner).\n\n";

    # Write logfile
    foreach ( split( /\n/, $warning ) ) {
        $log->warning("$_\n");
    }
    $log->information("###########################\n");
    foreach ( split( /\n/, $info ) ) {
        $log->information("$_\n");
    }
    $log->information("###########################\n");

    # Prepare commands to fix the situation

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

END_OF_MKMERGE

    @mkci = ( <<"END_OF_MKCI" =~ m/^\s*(.+)/gm );
cleartool ci -nc \"$win32element\"
cleartool ci -nc .

END_OF_MKCI

    # Done our best, inform and get out

    $log->information( join '\n', ( @head, @mkmerge, @mkci ) );

    if ( $twincfg{AutoMerge} == 0 ) {

        # Inform only, and stop the operation
        exit 1;

    }

    if ( $twincfg{AutoMerge} == 1 ) {

        # Do the required merge, but leave checked out
        foreach (@mkmerge) {
            print "$_\n";
            my $retval;

            #            my $retval = qx($_);
            #            print     "$retval\n";
            system("$_");
            if ($?) {
                $log->error("The command [$_] didn't exit properly: $retval");
                die "ERROR. Read the logfile\n";
            }

        }
        $log->warning(
"Evil twin detected. We have tried to get around it, but haven't checked in the changes. Please verify, and check in if you are satisfied."
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

__END__
