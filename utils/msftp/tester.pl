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

use constant INI_NAME => '/users.ini';    # maps to values used by multisite defaults

my $puser   = 'praqma';
my $ppasw   = 'Praqma2007';
my $known   = '83.221.132.252';
my $srvpath = '/home/praqma/drop1';
my $target  = 'C:\mvfslogs';

my $pccObject = pcc->new;

my %psftp_known_hosts = $pccObject->get_psftp_known_hosts();

sub init_psftp_host {

    # first time psftp talks to a new host, we are prompted to save the certificate.
    # the entries can be found in registry, and we have captured them in %psftp_known_hosts
    # If the host is new, accept to save the certificate

    unless ( exists $psftp_known_hosts{$known} ) {
        my $cmd = "psftp.exe -pw $ppasw $puser\@$known";
        open( PS, "| $cmd" ) || die "Failed: $!\n";
        print PS "y\n";
        print PS "exit\n";

    }
}

sub get_psftp_files {
    my %retrieved_files = ();
    my $listcommands = File::Temp->new( TEMPLATE => 'temp_XXXXX', DIR => $ENV{TEMP}, SUFFIX => '.dat' );
    print $listcommands "dir $srvpath\n";
    print $listcommands "lcd $target\n";
    print $listcommands "mget $srvpath/*.*\n";
    print $listcommands "exit\n";

    my $cmd         = "psftp.exe -pw $ppasw -b $listcommands $puser\@$known";
    
    my @remotefiles = $pccObject->_cmd(command => $cmd);
    
    foreach (@remotefiles) {
 
        print "$_";
        next unless /^-/;
        my ( $size, $name ) = ( split( /\s+/, $_, 9 ) )[ 4, 8 ];
        chomp $name;
        $retrieved_files{$name} = $size;

    }

    my $deletecommands = File::Temp->new( TEMPLATE => 'temp_XXXXX', DIR => $ENV{TEMP}, SUFFIX => '.dat' );

    foreach ( keys %retrieved_files ) {
        my $file = "$target/$_";
        if ( -f $file ) {
            print $deletecommands "rm \"$srvpath/$_\"\n";
        }

    }
    print $deletecommands "exit\n";

    print qx(type "$deletecommands");

    $cmd         = "psftp.exe -pw $ppasw -b $deletecommands $puser\@$known";
    
    @remotefiles = $pccObject->_cmd(command => $cmd);
   
    foreach (@remotefiles) {
        print;
    }
}

sub put_psftp_files {
    my $deletecommands = File::Temp->new( TEMPLATE => 'temp_XXXXX', DIR => $ENV{TEMP}, SUFFIX => '.dat' );    
}




init_psftp_host();
get_psftp_files();
put_psftp_files();