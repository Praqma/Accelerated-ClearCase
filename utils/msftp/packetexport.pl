require 5.000;
use strict;

$| = 1;
our ( $Scriptdir, $Scriptfile, $parentdir );

BEGIN {
    use File::Basename;
    $Scriptdir  = dirname(__FILE__) . "\\";
    $Scriptfile = basename(__FILE__);
}

# Use clauses
use File::Basename;
use Getopt::Long;

use lib "$Scriptdir..//..";
use scriptlog;
use pcc 0.1007;

# use acc;
use constant TRANSPORT_HLTYPE => 'SpecialTransport';    # name of hyperlink type we recognize

### Global variables ###
my (
    $sw_run,                                            # required to run
    $sw_dryrun,                                         # only list selections
    $sw_help,                                           # display help
    $sw_verbose,
    $sw_debug,
    %options,                                           # list of command line options
    $synclistpgm,                                       # synclist pgram
    @normaltransport,                                   # list of replica that use default shipping
    %specialtransport,                                  # list of replica's that use non default
);

my $log       = scriptlog->new;
my $pccObject = pcc->new;

# File version
my $major   = 0;
my $minor   = 1;
my $build   = 1;
my $VERSION = $pccObject->format_version_number( $major, $minor, $build );

# Header history

my $header = <<ENDHEADER;
#########################################################################
#    Date:       2012-09-30
#    Author:     Jens Brejner, jbrejner\@praqma.net
#    Copyright:  Praqma A/S, Denmark
#    License:    GNU General Pulic License
#    Support:    http://www.praqma.com or mail: support\@praqma.net
#########################################################################
 
ENDHEADER

# Revision information
################################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2012-09-30  Jens Brejner   Initial Version (v 0.1001)
-------------------------------------------------------------------------
 
ENDREVISION

my $usage = <<ENDUSAGE;
$Scriptfile -lsquarantine [-autopurge [-sendmail] [-days DD] | -autorecover [-days DD] ] 
$Scriptfile -help
Auxiliary switches [-[no]debug | -[no]verbose | -[no]logfile [location]
 
ENDUSAGE

my $doc = <<ENDDOC;
-run                    Required. Process all vobs                 
-dryrun                Optional. List only the replicas that are found in each group
-help                   Only display the help you are now watching   
 
--- Auxiliary switches (can be omitted or used on all functions)---
 
-[no]logfile [location] Sets whether or not to create a logfile.
                        May define the name [and location] of the logfile.
                        Default value is the temp dir (usually under
                        users " doc &set ") and " view_q . pl [PID] . log "
 
-[no]verbose            Toggles verbose mode (log to STDOUT)
                        Default is on (for manual execution, verbose is recommended)
 
-[no]debug              Toggles debug mode (additional information + force logfile + verbose)
                        Default is off
 
ENDDOC

my @burnlicense = qx(cleartool lsvob 2>&1);

# Validate options
# TODO finish the validate_options function, currently we only get the options
#validate_options();

# define the path to sync_export_list.bat
$synclistpgm = GetListExportScript();

# get all the vobtags
my @vobtags = @{ $pccObject->get_vobtags() };

# sort replica's by transport type
get_candidates();

my %result = ();
print "For normal sync:\n";
foreach (@normaltransport) {
    /(.*)(@.*)/;
    push @{ $result{$2} }, $1;

}

foreach my $vob ( keys %result ) {
    my $first = pop @{ $result{$vob} };
    $first = $first . $vob;
    print join( ',', $first, @{ $result{$vob} } ) . "\n";

}

print "For special sync:\n";
%result = ();

foreach my $replica ( keys %specialtransport ) {
    my ( $sclass, $server, $path ) = split( /,/, $specialtransport{$replica} );
    print "Replica $replica should use storage class $sclass, to server $server in directory at $path\n ";
}

################################ SUBS ################################

sub add_normal {
    my %parms = @_;
    my $siblings = $pccObject->get_siblings( tag => $parms{vobtag} );
    if ($siblings) {
        foreach my $target ( split( /,/, $siblings ) ) {
            $target =~ s/(replica:)(.*)/$2/;
            push @normaltransport, $target unless exists $specialtransport{$target};

        }
    }
}

sub add_special {

    # Add record in %specialtransport if hyperlink is found
    my %parms = @_;
    my @specials = ( grep { /^->/ } $pccObject->ct( command => 'describe -short -ahlink ' . TRANSPORT_HLTYPE . " $parms{replica}" ) );
    foreach (@specials) {

        # each has the format: '-> replica:nightwalker@\enbase "ftp to here"'

        my ( $target, $instruction ) = $_ =~ /^->\s+(\S+)\s+"(.*)"$/;
        $target =~ s/(replica:)(.*)/$2/;
        $specialtransport{$target} = $instruction;
        $log->information("Added key $target with value $instruction in \%specialtransport") if $sw_debug;
    }
}

sub get_candidates {
    foreach my $tag (@vobtags) {

        # process vob only if it is replicated
        next unless ( $pccObject->IsReplicated( vobtag => $tag ) );

        my $replicaname = $pccObject->get_localreplica( tag => $tag );
        $log->information("Found a local replica name : [$replicaname] for vob $tag") if $sw_debug;

        # if hyperlink type exist from this replica to another, add the target to specialtransport
        add_special( replica => $replicaname );
        add_normal( vobtag => $tag );

    }
}

sub GetListExportScript {

    # We need "sync_export_list.bat" - check it exists
    my $pathstring = $pccObject->get_cchome();
    $log->information("Got [$pathstring] string back from  \$pccObject->get_cchome()") if $sw_debug;
    $pathstring = $pathstring . '\config\scheduler\tasks\sync_export_list.bat';
    $log->information("Changed it to [$pathstring]") if $sw_debug;
    if ( -f $pathstring ) {
        $log->information("[$pathstring] is an existing file") if ($sw_debug);
        return $pathstring;
    }
    else {
        $log->assertion_failed("[$pathstring] is not a existing file, and we need it. Quitting")

    }
}

sub validate_options {

    %options = (

        "run!"     => \$sw_run,        # run - wont process without
        "dryryn!"  => \$sw_dryrun,     # list findings only
        "help!"    => \$sw_help,       # display help
        "verbose!" => \$sw_verbose,    # more diagnostic output
        "debug!"   => \$sw_debug,      # all output
    );

    die "$usage" unless GetOptions(%options);

}
