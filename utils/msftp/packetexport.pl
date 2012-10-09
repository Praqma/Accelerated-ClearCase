require 5.000;
use strict;

$| = 1;
our ( $Scriptdir, $Scriptfile );

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

use lib "$Scriptdir../../praqma";
use scriptlog;
use pcc 0.1007;

use constant TRANSPORT_HLTYPE   => 'SpecialTransport';    # name of hyperlink type we recognize
use constant TRANSPORT_INCOMING => '/incoming';           # maps to values used by multisite defaults
use constant TRANSPORT_OUTGOING => '/outgoing';           # maps to values used by multisite defaults

### Global variables ###
my (
    $sw_run,                                              # required to run
    $sw_dryrun,                                           # only list selections
    $sw_help,                                             # display help
    $sw_verbose,
    $sw_debug,
    %options,                                             # list of command line options
    $synclistpgm,                                         # synclist pgram
    @normaltransport,                                     # list of replica that use default shipping
    %specialoutgoing,                                     # list of replica's that this replica should send to
    %specialincoming,                                     # list of replica's that this replica should receive from
    $ftpObject,                                           # ftp object
);

my $log       = scriptlog->new;
my $pccObject = pcc->new;

# File version
my $major   = 0;
my $minor   = 1;
my $build   = 3;
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
2012-09-30  Jens Brejner   Initial Version (v 0.1003)
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

warn "Whoah hardcoded user !\n";
my $puser       = 'jbr';
my $pass        = 'Praqma2';
my @burnlicense = qx(cleartool lsvob 2>&1);

# TODO finish the validate_options function, currently we only get the options

validate_options();

# Initialize the rest

my $cwd = getcwd();
$log->set_verbose($sw_verbose);
$log->enable(1);
$log->conditional_enable( ( $sw_verbose || $sw_debug ) );

# define the path to sync_export_list.bat
$synclistpgm = GetListExportScript();

my %storageclasses = $pccObject->get_multisite_class_bays();

# get all the vobtags
my @vobtags = @{ $pccObject->get_vobtags() };

# sort replica's by transport type
get_candidates();

get_from_ftp() if ( scalar( keys %specialoutgoing ) );

# Syncronize all the normally processed replica's by calling sync_list_export each relevant replica
create_default();

# Syncronize all the specially processed replica's by calling sync_list_export each relevant replica
create_special();

# Move created packages to ftp
send_to_ftp();

# get exit code and exit
exit $log->get_accumulated_errorlevel();

################################ SUBS ################################

sub get_name_only {
    my $full_replica = shift;
    my ($name, $junk) = split( '@', $full_replica, 2 );
    return $name;
} 

sub get_from_ftp {

    foreach my $replicalist ( keys %specialincoming ) {

        my ( $sclass, $server, $path ) = split( /,/, $specialincoming{$replicalist} );
        $log->assertion_failed("Cant find Storage bay for class $sclass") unless exists $storageclasses{$sclass};

        my $filesystempath = $storageclasses{$sclass} . TRANSPORT_INCOMING;
        chdir $filesystempath;

        my $dropname = get_name_only($replicalist);
        my $serverpath = "$path/to_$dropname";

        start_ftp( server => $server, user => $puser, password => $pass );
        $ftpObject->cwd("$serverpath") or $log->assertion_failed( "Cannot change directory $serverpath " . $ftpObject->message );



        opendir( DIR, "$filesystempath" );
        my @remotefiles = $ftpObject->ls();
        foreach (@remotefiles) {
            next unless ( $ftpObject->size($_) );

            if ( $ftpObject->get($_) ) {
                $log->information("Retrieved $_") if $sw_debug;
                $ftpObject->delete($_) or $log->warning("Couldn't delete $_");
            }
            else {
                $log->warning("Failed to retrieve $_: $ftpObject->message()  ");
            }    # end if

        }    # end foreach (@remotefiles)
        closedir(DIR);
        stop_ftp();
        chdir $cwd;

    }    # end foreach my $replicalist
}

sub send_to_ftp {
    foreach my $replicalist ( keys %specialoutgoing ) {

        my ( $sclass, $server, $path ) = split( /,/, $specialoutgoing{$replicalist} );
        $log->assertion_failed("Cant find Storage bay for class $sclass") unless exists $storageclasses{$sclass};

        my $filesystempath = $storageclasses{$sclass} . TRANSPORT_OUTGOING;
        chdir $filesystempath;

        my $dropname = get_name_only($replicalist);
        my $serverpath = "$path/to_$dropname";

        start_ftp( server => $server, user => $puser, password => $pass );
        $ftpObject->cwd("$serverpath") or $log->assertion_failed( "Cannot change directory $serverpath:" . $ftpObject->message );

        opendir( DIR, "$filesystempath" ) or die;

      FILE: while ( my $file = readdir(DIR) ) {
            next FILE if ( -z $file );

            if ( $ftpObject->put($file) ) {
                $log->information_always("Succesfully copied $file to $server in  $serverpath");
                unlink $file or $log->warning("Failed to delete $file from $filesystempath");
            }
            else {
                $log->warning( "Failed to copy file $file " . $ftpObject->message );
            }
        }

        closedir(DIR);
        stop_ftp();
        chdir $cwd;

    }

}

sub stop_ftp {

    $ftpObject->quit;
    $ftpObject->DESTROY;

}

sub start_ftp {

    my %parms = @_;

    # connect to ftp
    $ftpObject = Net::FTP->new( $parms{server}, Debug => 0 ) or $log->assertion_failed("Cannot connect to $parms{server}: $@");
    $ftpObject->login( $parms{user}, $parms{password} ) or $log->assertion_failed( "Cannot log in: " . $ftpObject->message );
    $ftpObject->binary();

}

sub create_special {
    print "For special sync:\n";
    my %result = ();

    foreach my $replicalist ( keys %specialoutgoing ) {

        # TODO What if this replica, has multiple special transports ?
        my ( $sclass, $server, $path ) = split( /,/, $specialoutgoing{$replicalist} );
        $log->information("Replica $replicalist uses storage class $sclass, to server $server in directory at $path\n") if $sw_debug;
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
        my $replicalist = join( ',', $first, @{ $result{$vob} } );
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
            push @normaltransport, $target unless exists $specialoutgoing{$target};

        }
    }
}

sub add_special {

    # Add records in %specialoutgoing and $specialincoming if hyperlink is found
    my %parms = @_;
    my ( @outgoing, @incoming );

    my $cmd     = "cleartool describe -ahlink " . TRANSPORT_HLTYPE . " $parms{replica}";
    my $pattern = '^\s+' . TRANSPORT_HLTYPE;

    my @retval = grep { /$pattern/ } $pccObject->ct( command => 'describe -ahlink ' . TRANSPORT_HLTYPE . " $parms{replica}" );

    foreach (@retval) {
        chomp;
        push @outgoing, $_ if (/->/);
        push @incoming, $_ if (/<-/);
    }

    foreach (@outgoing) {

        # @outgoing is empty if the replica does not have a  TRANSPORT_HLTYPE hyperlink
        # each has the format: '    SpecialTransport -> replica:nightwalker@\enbase "ftp,ftp.praqma.net,/array1/ccmsftp/drop1"'

        my ( $target, $instruction ) = $_ =~ /^.*->\s+(\S+)\s+"(.*)"$/;
        $target =~ s/(replica:)(.*)/$2/;
        $specialoutgoing{$target} = $instruction;

        $log->information("Added key $target with value $instruction in \%specialoutgoing") if $sw_debug;
    }

    foreach (@incoming) {

        # @incoming is empty if the replica does not have a  TRANSPORT_HLTYPE hyperlink
        # each has the format: '    SpecialTransport "ftp,ftp.praqma.net,/array1/ccmsftp/drop1" <- replica:nightwalker@\enbase'

        /^\s+\S+\s+"([^"]*)"\s+.*$/;
        my $instruction = $1;
        my $target      = $parms{replica};
        $target =~ s/(replica:)(.*)/$2/;
        $specialincoming{$target} = $instruction;

        $log->information("Added key $target with value $instruction in \%specialoutgoing") if $sw_debug;
    }
}

sub get_candidates {
    foreach my $tag (@vobtags) {

        # process vob only if it is replicated
        next unless ( $pccObject->IsReplicated( vobtag => $tag ) );

        my $replicaname = $pccObject->get_localreplica( tag => $tag );
        $log->information("Found a local replica name : [$replicaname] for vob $tag") if $sw_debug;

        # if hyperlink type exist from this replica to another, add the target to %specialoutgoing
        add_special( replica => $replicaname );
        add_normal( vobtag => $tag );

    }
}

sub GetListExportScript {

    # We need "sync_export_list.bat" - check it exists
    my $pathstring = $pccObject->get_cchome();
    $log->information("Got [$pathstring] string back from  \$pccObject->get_cchome()");    # if $sw_debug;
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
    $sw_verbose = $sw_debug ? $sw_debug : $sw_verbose;

}
