@rem = ' This is a perl script for NT and UNIX.
@echo off
goto endofperl
@rem ';

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
use File::Temp;
use Getopt::Long;
use Net::Ftp;
use Cwd;
use lib "$Scriptdir../../praqma";
use scriptlog;
use pcc 0.1007;
use constant TRANSPORT_HLTYPE   => 'SpecialTransport';    # name of hyperlink type we recognize
use constant TRANSPORT_INCOMING => '/incoming';           # maps to values used by multisite defaults
use constant TRANSPORT_OUTGOING => '/outgoing';           # maps to values used by multisite defaults
use constant INI_NAME           => '/users.ini';          # maps to values used by multisite defaults

### Global variables ###
my (
    $sw_run,                                              # required to run
    $sw_dryrun,                                           # only list selections
    $sw_help,                                             # display help
    $sw_verbose,
    $sw_debug,
    %options,                                             # list of command line options
    $cwd,                                                 # Current working directory
    @vobtags,                                             # Array of known vobtags
    $synclistpgm,                                         # synclist pgram
    @normaltransport,                                     # list of replica that use default shipping
    %storageclasses,                                      # list of storage classes and their storagebays
    %psftp_known_hosts,                                   # list of known sftp hosts (psftp saves their certificate in registry)
    %specialoutgoing,                                     # list of replica's that this replica should send to
    %specialincoming,                                     # list of replica's that this replica should receive from
    $ftpObject,                                           # ftp object
    %inicontents                                          # hash of contents from the ini file, filename is specified by constant INI_NAME
);
my $log       = scriptlog->new;
my $pccObject = pcc->new;

# File version
my $major   = 0;
my $minor   = 1;
my $build   = 5;
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
2012-11-15  Jens Brejner   Fix bug with with contact to sftp server (v 0.1005)
2012-09-30  Jens Brejner   Initial Version (v 0.1003)

-------------------------------------------------------------------------
 
ENDREVISION
my $usage = <<ENDUSAGE;
$Scriptfile -run [-debug] [-verbose] [-logfile path_to_log_file]
$Scriptfile -help
Auxiliary switches [-[no]debug | -[no]verbose | -[no]logfile [location]
 
ENDUSAGE
my $doc = <<ENDDOC;
-run                    Required. Process all vobs                 
-help                   Only display the help you are now watching   
 
--- Auxiliary switches (can be omitted or used on all functions)---
 
-logfile <location>     Sets whether or not to create specific logfile.
                        Default value is the users temp dir 
-verbose                Toggles verbose mode (log to STDOUT)
                        Default is on (for manual execution, verbose is recommended)
-debug                  Toggles debug mode (additional information + force logfile + verbose)
                        Default is off
 
ENDDOC

### Main starts here, continues till ### SUBS ###

# Check input parameters
validate_options();

# Initialize the rest
initialize();

# sort replica's by transport type
get_candidates();

# Collect incoming packages
fetch_incoming() if ( scalar( keys %specialincoming ) );

# Syncronize all the normally processed replica's by calling sync_list_export each relevant replica
create_default();

# Create packages for sending via (s)ftp calling sync_list_export each relevant replica's and sclass
create_special();

# Move created packages to ftp
send_outgoing();

process_clearquest();

# get exit code and exit
my $exitval = $log->get_accumulated_errorlevel();
$log->information("All processing finished, exiting with code: $exitval") if ( $exitval eq 0 );
$log->warning("All processing finished, exiting with code: $exitval") if ( $exitval gt 0 );
exit $log->get_accumulated_errorlevel();

### SUBS ###

sub process_clearquest {
    $log->information("Looking for scripts to process ClearQuest Multisite packages") if $sw_debug;

    opendir( DIR, "$cwd" ) or die;
  FILE: while ( my $file = readdir(DIR) ) {
        next FILE unless ( $file =~ /^sync_cq/ );
        $log->information("Found $file") if $sw_debug;
        my @reply = $pccObject->_cmd( command => $file );
        $log->information( join( '', @reply ) ) if $sw_debug;
    }
    closedir(DIR);
}

sub get_sclass_for_incoming {

    my $replica = shift;
    my $pattern = qr/^([^@]+)([@][\\]\S+$)/o;
    my $tag;
    $log->information("Finding storageclass to import to for replica $replica") if $sw_debug;
    if ( $replica =~ $pattern ) {
        $tag = $2;
        $log->information("The vobtag is $tag") if $sw_debug;
    }
    $log->assertion_failed( "Failed to get vobtag at line " . __LINE__ ) unless ($tag);

    foreach ( keys %specialoutgoing ) {
        $_ =~ $pattern;
        my $receiving_vob = $2;
        if ( $tag eq $receiving_vob ) {
            $log->information("Found $_ with value $specialoutgoing{$_}") if $sw_debug;
            return ( split( ',', $specialoutgoing{$_} ) )[0];
        }
    }

    # We should never get here, we were supposed to return when finding the the sclass in loop above
    # so if we get here - something is wrong
    $log->assertion_failed("Failed to find storageclass for import for replica $replica, can't continue");
}

sub send_outgoing {
    foreach my $replica ( keys %specialoutgoing ) {

        # each replica that could have incoming packages to local replica
        my $server = ( split( /,/, $specialoutgoing{$replica} ) )[1];
        if ( $server =~ /^ftp:\/\//i ) {
            $log->information("Moving packages for $replica to $server");
            send_to_ftp($replica);
            next;
        }
        if ( $server =~ /^sftp:\/\//i ) {
            $log->information("Moving packages for $replica $server");
            put_sftp_files($replica);
            next;
        }
        if ( $server !~ /^ftp:\/\//i || $server !~ /^sftp:\/\//i ) {
            $log->warning("Server type $server is not supported, the information was found on replica:$replica ");
        }
    }
}

sub init_psftp_host {

    # first time psftp talks to a new host, we are prompted to save the certificate.
    # the entries can be found in registry, and we have captured them in %psftp_known_hosts
    # If the host is new, accept to save the certificate
    my %parms = @_;
    unless ( exists $psftp_known_hosts{ $parms{server} } ) {
        my $cmd = "psftp.exe -pw $parms{password} $parms{user}\@$parms{server} 2>&1";
        open( PS, "| $cmd" ) || $log->assertion_failed("Command $cmd Failed: $!\n");
        print PS "y\n";
        print PS "exit\n";
        close(PS);
        %psftp_known_hosts = $pccObject->get_psftp_known_hosts();
    }
}

sub get_from_sftp {
    my $replica    = shift;
    my $inisection = "replica:$replica";
    my $s_user     = ${ $inicontents{$inisection} }{user};
    my $s_pass     = ${ $inicontents{$inisection} }{password};
    my ( $server, $srvpath ) = ( split( /,/, $specialincoming{$replica} ) )[ 1, 2 ];
    my $host            = ( split( '//', $server ) )[1];
    my $sclass          = get_sclass_for_incoming($replica);
    my $target          = $storageclasses{$sclass} . TRANSPORT_INCOMING;
    my %files_on_server = ();
    init_psftp_host( server => $host, user => $s_user, password => $s_pass );

    # psftp is not scriptable, but can process commands from a file. Build the command in a temp file
    my $listcommands = File::Temp->new( TEMPLATE => 'temp_XXXXX', DIR => $ENV{TEMP}, SUFFIX => '.dat' );
    print $listcommands "dir $srvpath\n";
    print $listcommands "lcd $target\n";
    print $listcommands "mget $srvpath/*\n";
    print $listcommands "exit\n";
    my $cmd = "psftp.exe -pw $s_pass -b $listcommands $s_user\@$host";
    my @remotefiles = $pccObject->_cmd( command => $cmd );
    chomp @remotefiles;

    # in the command output (stored in @remotefiles, we have the filenames and their size, put the info into %files_on_server
    foreach (@remotefiles) {
        if (/^Unable to/i) {
            $log->assertion_failed( "Unexpected psftp reply:\n" . join( '', @remotefiles ) );
        }
        $log->information("$_");
        next unless /^-/;
        my ( $size, $name ) = ( split( /\s+/, $_, 9 ) )[ 4, 8 ];
        chomp $name;
        $files_on_server{$name} = $size;
    }
    my $deletecommands = File::Temp->new( TEMPLATE => 'temp_XXXXX', DIR => $ENV{TEMP}, SUFFIX => '.dat' );

    # Check that the files we retrieved match on size, then prepare to delete them from sftp server
    foreach ( keys %files_on_server ) {
        my $file = "$target/$_";
        if ( ( -f $file ) && ( ( -s $file ) eq $files_on_server{$_} ) ) {
            print $deletecommands "rm \"$srvpath/$_\"\n";
        }
    }
    print $deletecommands "exit\n";
    $cmd = "psftp.exe -pw $s_pass -b $deletecommands $s_user\@$host";
    @remotefiles = $pccObject->_cmd( command => $cmd );
    $log->information( join( '', @remotefiles ) );
}

sub put_sftp_files {
    my $replica    = shift;
    my $inisection = "replica:$replica";
    my $s_user     = ${ $inicontents{$inisection} }{user};
    my $s_pass     = ${ $inicontents{$inisection} }{password};
    my ( $sclass, $server, $srvpath ) = split( /,/, $specialoutgoing{$replica} );
    my $host            = ( split( '//', $server ) )[1];
    my $source          = $storageclasses{$sclass} . TRANSPORT_OUTGOING;
    my %files_on_server = ();

    # Accept sftp server's certificate
    init_psftp_host( server => $host, user => $s_user, password => $s_pass );

    # psftp is not scriptable, but can process commands from a file. Build the command in a temp file
    my $putcommands = File::Temp->new( TEMPLATE => 'temp_XXXXX', DIR => $ENV{TEMP}, SUFFIX => '.dat' );
    print $putcommands "lcd $source\n";    # During sftp session, change to local directory of the outgoing files
    print $putcommands "cd $srvpath\n";    # During sftp session, change to server folder
    chdir "$source";
    opendir( DIR, "$source" ) or die;
  FILE: while ( my $file = readdir(DIR) ) {
        next FILE if ( -z $file );

        # Delete the shipping order files, we don't need them
        if ( $file =~ /^sh_o_sync_/ ) {
            $log->information("Removed unnessecary shipping order file: $file") if $sw_debug;
            unlink $file or $log->warning("Trouble removing $file: $!\n");
            next;
        }
        print $putcommands "put $file\n";    # put each file found
    }
    chdir $cwd;
    closedir(DIR);
    print $putcommands "dir $srvpath\n";
    print $putcommands "exit\n";
    my $cmd = "psftp.exe -pw $s_pass -b $putcommands $s_user\@$host";
    my @reply = $pccObject->_cmd( command => $cmd );
    chomp @reply;

    # in the command output (stored in @reply, we have the filenames and their size, put the info into %files_on_server
    foreach (@reply) {
        if (/^Unable to/i) {
            $log->assertion_failed( "Unexpected psftp reply:\n" . join( '', @reply ) );
        }
        $log->information("$_");
        next unless /^-/;
        my ( $size, $name ) = ( split( /\s+/, $_, 9 ) )[ 4, 8 ];
        chomp $name;
        $files_on_server{$name} = $size;
    }

    # Check that the files we sent match on size, if size and name matches, delete local file.
    foreach ( keys %files_on_server ) {
        my $file = "$source/$_";
        if ( ( -f $file ) ) {
            if ( ( -s $file ) eq $files_on_server{$_} ) {
                if ( unlink $file ) {
                    $log->information("$file has been transferred to $server");
                }
                else {
                    $log->warning("$file was not removed, although it was properly transferred to $server");
                }
            }
            else {
                $log->warning("$file was not removed, size of transferred file does not mathc local file size");
            }
        }
    }
}

sub fetch_incoming {
    my %seen_classes;
    foreach my $replica ( keys %specialincoming ) {

        # each replica that could have incoming packages to local replica
        my ($server) = ( split( /,/, $specialincoming{$replica} ) )[1];
        chomp $server;

        if ( $server =~ /^ftp:\/\//i ) {
            $log->information("Checking for incoming packages for $replica at $server");
            get_from_ftp($replica);
            next;
        }
        if ( $server =~ /^sftp:\/\//i ) {
            $log->information("Checking for incoming packages for $replica at $server");
            get_from_sftp($replica);
            next;
        }
        if ( $server !~ /^ftp:\/\//i || $server !~ /^sftp:\/\//i ) {
            $log->warning("Server type $server is not supported, the information was found on replica:$replica ");
        }
    }

    foreach ( keys %specialoutgoing ) {

        # find local storage classes in use
        my ($class) = ( split( /,/, $specialoutgoing{$_} ) )[0];
        $seen_classes{$class}++;
    }
    foreach ( keys %seen_classes ) {

        $log->information("Importing for storageclass $_ ") if $sw_debug;
        my $cmd = " syncreplica -import -receive -sclass $_";
        my @importmsg = $pccObject->mt( command => $cmd );
        $log->information( join( '', @importmsg ) );
    }
}

sub get_name_only {
    my $full_replica = shift;
    my ( $name, $junk ) = split( '@', $full_replica, 2 );
    return $name;
}

sub get_from_ftp {
    my $replica = shift;
    my $sclass  = get_sclass_for_incoming($replica);
    my ( $server, $path ) = ( split( /,/, $specialincoming{$replica} ) )[ 1, 2 ];
    $log->assertion_failed("Cant find Storage bay for class $sclass") unless exists $storageclasses{$sclass};
    my $filesystempath = $storageclasses{$sclass} . TRANSPORT_INCOMING;
    chdir $filesystempath;
    my $inisection = "replica:$replica";
    my $dropname   = get_name_only($replica);
    my $serverpath = "$path/to_$dropname";
    $log->information("Connecting to $server as ${ $inicontents{$inisection} }{user}");
    start_ftp( server => $server, user => ${ $inicontents{$inisection} }{user}, password => ${ $inicontents{$inisection} }{password} );
    $ftpObject->cwd("$serverpath") or $log->assertion_failed( "Cannot change directory $serverpath " . $ftpObject->message );
    opendir( DIR, "$filesystempath" );
    my @remotefiles = $ftpObject->ls();

    if ( scalar(@remotefiles) ) {
        $log->information( "Found files on $server:\n" . join( '\n', @remotefiles ) ) if $sw_debug;
        foreach (@remotefiles) {
            next unless ( $ftpObject->size($_) );
            if ( $ftpObject->get($_) ) {
                $log->information("Retrieved $_") if $sw_debug;
                $ftpObject->delete($_) or $log->warning("Couldn't delete $_");
            }
            else {
                $log->warning("Failed to retrieve $_: $ftpObject->message()  ");
            }
        }

    }
    else {
        $log->information("Did not find files on $server in folder $serverpath") if $sw_debug;
    }

    closedir(DIR);
    stop_ftp();
    chdir $cwd;
}

sub load_user_credentials {

    $log->information("Reading Credentials from users.ini") if $sw_debug;

    # Read user credentials from ini file
    my $inifile = dirname($0) . INI_NAME;
    %inicontents = $pccObject->read_ini( file => $inifile );

    # Change the keys of the anonymous hashes to lower case, need that for proper lookup later
    foreach my $k ( keys %inicontents ) {
        $log->information("Users.ini had section [$k]") if $sw_debug;
        foreach ( keys %{ $inicontents{$k} } ) {
            ${ $inicontents{$k} }{ lc($_) } = delete ${ $inicontents{$k} }{$_};
            $log->information( "Key [" . lc($_) . "] has value [" . ${ $inicontents{$k} }{ lc($_) } . "]" ) if $sw_debug;
        }
    }
}

sub send_to_ftp {
    my $replicalist = shift;
    my ( $sclass, $server, $path ) = split( /,/, $specialoutgoing{$replicalist} );
    $log->assertion_failed("Cant find Storage bay for class $sclass") unless exists $storageclasses{$sclass};
    my $filesystempath = $storageclasses{$sclass} . TRANSPORT_OUTGOING;
    chdir $filesystempath;
    my $inisection = "replica:$replicalist";
    my $dropname   = get_name_only($replicalist);
    my $serverpath = "$path/to_$dropname";
    $log->information("Opening connection to $server as ${ $inicontents{$inisection} }{user} ");
    start_ftp( server => $server, user => ${ $inicontents{$inisection} }{user}, password => ${ $inicontents{$inisection} }{password} );
    $ftpObject->cwd("$serverpath") or $log->assertion_failed( "Cannot change directory $serverpath:" . $ftpObject->message );
    opendir( DIR, "$filesystempath" ) or die;
  FILE: while ( my $file = readdir(DIR) ) {
        next FILE if ( -z $file );

        # Delete the shipping order files
        if ( $file =~ /^sh_o_sync_/ ) {
            $log->information_always("Deleting unnessecary shipping order file: $file") if $sw_debug;
            unlink $file or $log->warning("Trouble removing $file: $!");
            next;
        }
        $log->information("Found file to be uploaded: $file") if $sw_debug;
        if ( $ftpObject->put($file) ) {
            $log->information_always("Succesfully copied $file to $server in  $serverpath");
            unlink $file or $log->warning("Failed to delete $file from $filesystempath");
        }
        else {
            $log->warning( "Failed to copy file $file " . $ftpObject->message );
        }
    }
    closedir(DIR);
    $log->information("Done looking for uploadable files") if $sw_debug;
    stop_ftp();
    chdir $cwd;
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
    my %result = ();

    foreach my $replicalist ( keys %specialoutgoing ) {

        # TODO What if this replica, has multiple special transports ?
        my ( $sclass, $server, $path ) = split( /,/, $specialoutgoing{$replicalist} );
        $log->information("Replica $replicalist uses storage class $sclass, to server $server in directory at $path\n") if $sw_debug;
        my @retval = grep { !/^$/ } qx(\"$synclistpgm\" -ship -sclass $sclass -replicas $replicalist 2>&1);
        chomp @retval;
        $log->information( join( '', @retval ) ) if ( $sw_debug && ( scalar(@retval) ) );
    }
}

sub create_default {

    # Process normal syncs
    my %result = ();
    $log->information("Processing replica's for normal syncronization");
    foreach (@normaltransport) {
        /(.*)(@.*)/;
        push @{ $result{$2} }, $1;
    }
    foreach my $vob ( keys %result ) {
        my $first = pop @{ $result{$vob} };
        $first = $first . $vob;
        my $replicalist = join( ',', $first, @{ $result{$vob} } );
        $log->information("Calling for standard processing: [$replicalist]") if $sw_debug;
        my @retval = grep { !/^$/ } qx(\"$synclistpgm\" -replicas $replicalist 2>&1);
        chomp @retval;
        $log->information( join( '', @retval ) ) if ( $sw_debug && ( scalar(@retval) ) );
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
    my @retval  = grep { /$pattern/ } $pccObject->ct( command => 'describe -ahlink ' . TRANSPORT_HLTYPE . " $parms{replica}" );
    foreach (@retval) {
        chomp;
        push @outgoing, $_ if (/->/);
        push @incoming, $_ if (/<-/);
    }
    foreach (@outgoing) {

        # @outgoing is empty if the replica does not have a  TRANSPORT_HLTYPE hyperlink
        # each has the format: '    SpecialTransport -> replica:nightwalker@\enbase "ftp,sftp://ftp.praqma.net,/array1/ccmsftp/drop1"'
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
        $log->information("Added key $target with value $instruction in \%specialincoming") if $sw_debug;
    }
}

sub get_candidates {

    # Find replicated vobs.
    #
    foreach my $tag (@vobtags) {
        $log->information("Checking vobtag $tag") if $sw_debug;

        # process vob only if it is replicated
        next unless ( $pccObject->IsReplicated( vobtag => $tag ) );
        my $replicaname = $pccObject->get_localreplica( tag => $tag );
        $log->information("Found a local replica name : [$replicaname] for vob $tag") if $sw_debug;

        # if hyperlink type SpecialTransport exist from this replica to another, add the target to %specialoutgoing
        add_special( replica => $replicaname );
        add_normal( vobtag => $tag );
    }
}

sub GetListExportScript {

    # We need "sync_export_list.bat" - check it exists
    $log->information("Looking for sync_export_list.bat") if $sw_debug;
    my $pathstring = $pccObject->get_cchome();
    $log->information("Got [$pathstring] string back from  \$pccObject->get_cchome()") if $sw_debug;
    $pathstring = $pathstring . '\config\scheduler\tasks\sync_export_list.bat';
    $log->information("Changed it to [$pathstring]") if $sw_debug;
    if ( -f $pathstring ) {
        $log->information("[$pathstring] is an existing file") if ($sw_debug);
        return $pathstring;
    }
    else {
        $log->assertion_failed("[$pathstring] is not a existing file, and we need it. Quitting");
    }
}

sub initialize {
    die "$0 is only tested on Windows" unless $^O =~ /^MSWin/;

    $cwd = getcwd();
    $log->set_verbose($sw_verbose);
    $log->enable(1);
    $log->conditional_enable( ( $sw_verbose || $sw_debug ) );
    load_user_credentials();

    # define the path to sync_export_list.bat
    $synclistpgm       = GetListExportScript();
    %storageclasses    = $pccObject->get_multisite_class_bays();
    %psftp_known_hosts = $pccObject->get_psftp_known_hosts();

    # get all the vobtags
    @vobtags = @{ $pccObject->get_vobtags() };
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
    ( print "$usage\n$doc" && exit 0 ) if ($sw_help)

}

__END__
:endofperl
pushd "%~dp0"
ratlperl %0 %*
popd
