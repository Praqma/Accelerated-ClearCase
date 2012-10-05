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
use Net::Ftp;
use Cwd;

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

my $puser = 'jbr';
my $pass  = 'Praqma2';

warn "Whoah hardcoded user !\n";

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
my $cwd         = getcwd();

# Validate options
# TODO finish the validate_options function, currently we only get the options
#validate_options();

# define the path to sync_export_list.bat
$synclistpgm = GetListExportScript();

# get all the vobtags
my @vobtags = @{ $pccObject->get_vobtags() };

# sort replica's by transport type
get_candidates();

if ( scalar( keys %specialtransport ) ) {
    print "Something is special\nWe should try to import\n";
}

create_default();

create_special();

send_ftp();

################################ SUBS ################################

sub send_ftp {
    my %storageclasses = $pccObject->get_multisite_class_bays();

    foreach my $replicalist ( keys %specialtransport ) {

        # TODO What if this replica, has multiple special transports ?
        my ( $sclass, $server, $path ) = split( /,/, $specialtransport{$replicalist} );
        $log->assertion_failed("Cant find Storage bay for class $sclass") unless exists $storageclasses{$sclass};

        # connect to ftp

        my $ftp = Net::FTP->new( $server, Debug => 0 ) or $log->assertion_failed("Cannot connect to $server: $@");
        $ftp->login( $puser, $pass ) or $log->assertion_failed("Cannot login  $ftp->message");
        $ftp->cwd("$path/outgoing") or $log->assertion_failed("Cannot change directory $path/outgoing $ftp->message");
        $ftp->binary();

        chdir "$storageclasses{$sclass}/outgoing";
        opendir( DIR, "$storageclasses{$sclass}/outgoing" );

      FILE: while ( my $file = readdir(DIR) ) {
            next FILE if ( -z $file );
            print "File is [$file]\n";

            if ( $ftp->put($file) ) {
                $log->information("Succesfully copied $file to $server $storageclasses{$sclass}/outgoing") if $sw_debug;
                unlink $file or $log->warning("Failed to delete $storageclasses{$sclass}/outgoing/$file");
            }
            else {
                $log->warning("Failed to copy file $file $ftp->message");
            }
        }

        chdir $cwd;
        closedir(DIR);
        $ftp->quit;

        #$log->information( join @retval) if $sw_debug;

    }

}

sub create_special {
    print "For special sync:\n";
    my %result = ();

    foreach my $replicalist ( keys %specialtransport ) {

        # TODO What if this replica, has multiple special transports ?
        my ( $sclass, $server, $path ) = split( /,/, $specialtransport{$replicalist} );
        $log->information("Replica $replicalist should use storage class $sclass, to server $server in directory at $path\n") if $sw_debug;
        my @retval = qx(\"$synclistpgm\" -ship -sclass $sclass -replicas $replicalist 2>&1);
        $log->information( join @retval ) if $sw_debug;

    }
}

sub create_default {

    # Process normal syncs
    my %result = ();
    print "\nProcess normal syncs:\n";
    foreach (@normaltransport) {
        /(.*)(@.*)/;
        push @{ $result{$2} }, $1;

    }

    foreach my $vob ( keys %result ) {
        my $first = pop @{ $result{$vob} };
        $first = $first . $vob;
        my $replicalist = join( ',', $first, @{ $result{$vob} } ) . "\n";
        $log->information("Calling for standard processing: [$replicalist]") if $sw_debug;
        my @retval = qx(\"$synclistpgm\" -replicas $replicalist 2>&1);
        $log->information( join @retval ) if $sw_debug;
    }

}

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
