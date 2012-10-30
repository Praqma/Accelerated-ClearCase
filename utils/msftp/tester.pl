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

use constant INI_NAME => '/users.ini';    # maps to values used by multisite defaults

my $pccObject = pcc->new;

# Read user credentials from ini file
my $inifile = dirname($0) . INI_NAME;
my %inicontents = $pccObject->read_ini( file => $inifile );
foreach my $k ( keys %inicontents ) {

    foreach ( keys %{ $inicontents{$k} } ) {
        ${ $inicontents{$k} }{ lc($_) } = delete ${ $inicontents{$k} }{$_};
    }

}

foreach my $k ( keys %inicontents ) {
    print "Section $k has keys:\n";
    foreach ( keys %{ $inicontents{$k} } ) {
        print "Key: $_ has value  ${$inicontents{$k}}{$_}\n";

    }
}

