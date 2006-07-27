######################## STANDARD STUFF ##############################
#
require 5.001;
use strict;

BEGIN {

    # Ensure that the view-private file will get named back on rejection.
    END {
        rename( "$ENV{CLEARCASE_PN}.mkelem", $ENV{CLEARCASE_PN} )
          if $? && !-e $ENV{CLEARCASE_PN} && -e "$ENV{CLEARCASE_PN}.mkelem";
    }
}

our( $Scriptdir, $Scriptfile );

BEGIN {

    # Capture current working directory, to be used in the "use lib" statement
    # following this BEGIN block
    $0 =~ /(.*[\/\\])(.*)$/;
    $Scriptdir  = $1;
    $Scriptfile = $2;
}

use lib $Scriptdir . "..\\PraqmaLib";

# Use clauses
use scriptlog;
use trigger_utils;

# File version
our $VERSION = "1.0";
our $BUILD   = "18";    # Praqma SVN repoistory revision

# Support trigger_utils::enable_install()
our $TRIGGER_NAME    = "STOP_TWIN";                                        #Required if you call trigger_utils::enable_install()
our $TRIGGER_INSTALL = "mktrtype -preop lnname -element -all vob:both";    #Required if you call trigger_utils::enable_install()

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$BUILD
#     This script is intended as trigger script for the
#     $TRIGGER_NAME trigger which prevents creation of
#     evil twins in ClearCase
#
#     Date:       2008-10-24
#     Author:     Jens Brejner, jbrejner\@praqma.net
#     Copyright:  Jens Brejner
#     License:    GNU General Pulic License
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
-------------------------  ----------------------------------------------
ENDREVISION

# 	Version 1.0.18 has been tested and verified on ClearCase LT 6.16.
#	There is one known issue if running the script on ClearCase version 7.*, which is
#	the formatting of the messsage box (clearprompt). If opgrading to CC version 7 the
#	double-escaped newlines should only be ecaped once, that means; expect to change
#	'\\n' to '\n' when found in the definition of $prompt

my $debug          = 1;    # Write more messages to the log file
my $verbose_mode   = 1;    # When verbose is on messages are wittten to console as well as logfile
my $case_sensitive = 0;    # 1 means Case Sensitive name matching

if ( $ENV{'DEBUG_STOP_TWIN'} ) { $debug = 1; }

enable_install();
require_trigger_context();

# Prepare logging capabilities
our $log = scriptlog->new;
$log->conditional_enable();
$verbose_mode && $log->set_verbose($verbose_mode);
$debug
  && do {
    $log->enable();
    $log->dump_ccvars();
    $log->set_verbose($verbose_mode);
    $log->information("DEBUG is ON\n");
  };

# Check for valid semaphore file, so trigger could be bypassed
my $backdoor = enable_semaphore_backdoor();

if ($backdoor) {

    #        Found valid semaphore file
    #        Format message, write to log, allow operation and quit

    my $msg = " Triggerscript " . uc($Scriptfile) . " \\n";
    $msg = "$msg was ignored for:\\n";
    $msg = "$msg $ENV{'CLEARCASE_PN'}\\n";
    $msg = "$msg by a valid semaphore file:\\n";
    $msg = "$msg $backdoor\\n";
    my $log = scriptlog->new;
    $log->enable();

    foreach ( split ( /\n/, $msg ) ) {
        $log->information("$_\n");
    }
    $msg = "$msg\\n\\nAction is logged in logfile:\\n" . $log->get_logfile;
    `clearprompt proceed -type ok -mask proceed -default proceed -newline -pre -pro "$msg"`;
    $log->DESTROY();
    exit 0;
}

# No valid backdoor, prepare to look duplicate name.
my ( $dir_delim, $possible_dupe, $dupver );
my $viewkind = $ENV{CLEARCASE_VIEW_KIND};
my $pathname = $ENV{CLEARCASE_PN};
my $sfx      = $ENV{'CLEARCASE_XN_SFX'} ? $ENV{'CLEARCASE_XN_SFX'} : '@@';

############################

if ( $ENV{'OS'} =~ /[Ww]indows*/ ) {

    # Convert any "X:\view_tag\vob_tag\.\*" to "X:\view_tag\vob_tag\*"
    $pathname =~ s/\\.\\/\\/;
    $dir_delim = "\\";
} else {
    $dir_delim = "/";
}
$debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$pathname is now [$pathname]\n" );

# split element name in dir and leaf
$pathname =~ /(.*)([\/\\])(.*)$/;
my $parent  = $1;
my $element = $3;

$debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$parent is now [$parent]\n" );
$debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$element is now [$element]\n" );

# Make parent directory DNA
my $parent_dna = "$parent" . "$dir_delim" . ".$sfx";
$debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$parent_dna is now [$parent_dna]\n" );

# Are we in a snapshot view?
my $snapview;
if ( exists( $ENV{'CLEARCASE_VIEW_KIND'} ) && $ENV{'CLEARCASE_VIEW_KIND'} ne 'dynamic' ) {
    $snapview = 1;
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Viewtype is SNAPSHOT\n" );
} else {
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Viewtype is DYNAMIC\n" );

    # The 2nd test is a special case for the vob root.
    $snapview = !-e "$parent$sfx/main" && !-e "$parent/$sfx/main";
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Value of \$snapview after vob root test is [$snapview]\n" );
}

# Now search for evil twin
my $found = 0;
my $pattern;
if ($case_sensitive) {
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Case sensitive matching is performed\n" );
    $pattern = "$element$sfx";
} else {
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Case INSENSITIVE matching is performed\n" );
    $pattern = "(?i)$element$sfx";
}

$debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$pattern is [$pattern]\n" );

foreach my $branchversion ( reverse qx(cleartool lsvtree -a -s -obs -nco "$parent_dna") ) {
    chomp $branchversion;
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Looking at \$branchversion: $branchversion\n" );
    chomp( my @match = grep /$pattern$/, `cleartool ls -s \"$branchversion\"` );
    if (@match) {
        $dupver = $match[$#match];
        $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$dupver before = [$dupver]\n" );
        $dupver =~ s/\\/\//g;    # normalize path sep
        $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$dupver normalized = [$dupver]\n" );
        $dupver =~ s/(.*)($sfx)$/$1/;    # strip directory part
        $found = $dupver;
        $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$dupver after = [$dupver]\n" );
        last;
    }
}

# No duplicate element is found on invisible branches
# Allow the creation of the element.
exit 0 unless $found;

# Possible duplicate element is found - start logging.
$log->enable();
my $user      = "$ENV{'CLEARCASE_USER'}";
my $pop_kind  = "$ENV{'CLEARCASE_POP_KIND'}";
my $vob_owner = `cleartool desc -fmt %u vob:$ENV{'CLEARCASE_VOB_PN'}`;

my $prompt = " Trigger $TRIGGER_NAME prevented operation [$pop_kind]\\n";
$prompt = "$prompt because an evil twin possibility was detected:\\n\\n";

if ( $pop_kind eq "mkelem" ) {

    # From a mkelem command
    $prompt = "$prompt The name: [$element]\\n";

} else {

    # From a "ln", "ln -s" or "mv" command
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Operation is not mkelem, but $pop_kind\n" );
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$ENV{'CLEARCASE_PN2'} is [$ENV{'CLEARCASE_PN2'}]\n" );
    $ENV{'CLEARCASE_PN2'} =~ /(.*[\/\\])(.*)$/;
    my $old_path_name = $1;
    chomp( my $old_element_name = $2 );
#	Rev 18 take out
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$old_path_name = [$old_path_name]\n" );
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$old_element_name = [$old_element_name]\n" );


    if ( !$pop_kind || ( $pop_kind eq "rmname" ) || ( $pop_kind eq "mkslink" ) ) {

        $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Operation is not mkelem, but $pop_kind\n" );
        $prompt = "$prompt The element name [$element]\\n";

    }
}

$prompt = "$prompt ALREADY exists for the directory:\\n [$parent]\\n";
$prompt = "$prompt in another branch as:\\n";
$prompt = "$prompt [$found].\\n";
$prompt = "$prompt \\n";
$prompt = "$prompt NOTE:  If you feel you really need to perform this action\\n";
$prompt = "$prompt e-mail the VOB_OWNER ($vob_owner).\\n\\n";

foreach ( split ( /\\n/, $prompt ) ) {
    $log->warning("$_\n");
}

$prompt = "$prompt Action is logged in logfile:\\n " . $log->get_logfile;

`clearprompt yes_no -pro \"$prompt\" -type error -mask abort -default abort -newline -prefer_gui`;
$log->DESTROY();

# Stop operation
exit 1;

#################################################################################################################
