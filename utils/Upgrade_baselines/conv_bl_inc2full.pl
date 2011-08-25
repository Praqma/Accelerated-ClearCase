use strict;

use strict;
our ( $_packagedir, $_packagefile );

BEGIN {
  use File::Basename;
  ( $_packagefile, $_packagedir ) = fileparse(__FILE__);
}

use lib "$_packagedir";
use lib "$_packagedir\\..\\..";

use praqma::pcc;

my $pccobj  = pcc->new();
my $t_begin = time();

my (@comps);
foreach (@{$pccobj->get_pvobs()}) {
  push @comps, @{$pccobj->get_components()};
}

my @comps = `cleartool lscomp -s  -invob $pvob`;

if ( $ARGV[0] ne "" ) {
  print "Filter: '$ARGV[0]'\n";
  @comps = grep( /$ARGV[0]/, @comps );
}

print "Found " . scalar(@comps) . " components that matched the filter\n";

foreach (@comps) {
  print "\t$_";
}

print "Processing " . scalar(@comps) . " components\n";

our $t_elapsed = time() - $t_begin;
print "Elapsed time (sec): $t_elapsed\n";

foreach (@comps) {
  chomp($_);
  my $comp = "component:$_\@$pvob";
  my $dot;
  print "############################################\n" . "Getting baselines in $comp\n";
  my @bls = `cleartool lsbl -s -component $comp`;
  my @inc_bls;

  $t_elapsed = time() - $t_begin;
  print "Elapsed time (sec): $t_elapsed\n";

  print "Processing " . scalar(@bls) . " baselines\n";

  print "Looking for those which are incrementally labeled\n";
  foreach (@bls) {
    chomp($_);
    my $bl = "baseline:$_\@$pvob";
    our $cmd = "cleartool desc -fmt \"[%[label_status]p] %n\\n\" $bl";
    $_ = `$cmd`;

    $dot = ".";
    (/\[Incrementally Labeled\]/) && do {
      push @inc_bls, $bl;
      $dot = "+";
    };
    print $dot;

  }

  print "\n";
  $t_elapsed = time() - $t_begin;
  print "Elapsed time (sec): $t_elapsed\n";

  print "Processing " . scalar(@inc_bls) . " incrementally labeled baselines\n";

  foreach (@inc_bls) {
    my $cmd = "cleartool chbl -full $_ >nul";
    print $_. "\n";
    system($cmd);
  }
  $t_elapsed = time() - $t_begin;
  print "Elapsed time (sec): $t_elapsed\n";

}

