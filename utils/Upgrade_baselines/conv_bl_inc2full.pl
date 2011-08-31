use strict;
our ( $_packagedir, $_packagefile );

BEGIN {
  use File::Basename;
  ( $_packagefile, $_packagedir ) = fileparse(__FILE__);
}

use Getopt::Long;

# $_packagedir was defined in BEGIN block
use lib "$_packagedir";
use lib "$_packagedir\\..\\..";
use pcc;
use scriptlog;

#  Script version
my $major = 0;
my $minor = 0;
my $build = 3;
our $VERSION = pcc::format_version_number( $major, $minor, $build );

# Header history
our $header = <<ENDHEADER;
##############################################################################
#     $_packagefile version $VERSION
#     This script converts incrementally labelled baselines to fully
#     labelled
#     
#     Execute with -help switch to learn more
#
#     Date:       2011-08-29
#     Author:     Jens Brejner, email:jens.brejner\@praqma.net
#     Copyright:  Praqma A/S, Denmark
#     License:    GNU General Pulic License
#     Support:    http://www.praqma.info
##############################################################################
 
ENDHEADER

# Revision information
###############################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------------
2011-08-29  Jens Brejner   Initial version (0.0003)   
----------  -------------  ----------------------------------------------------
 
ENDREVISION

my $usage = <<ENDUSAGE;
Usage:

$_packagefile -help
$_packagefile -allvobs | -vob VOBTAG 
$_packagefile -component COMPONENT-IDENTIFIER 

Auxiliary switches [-debug]  
ENDUSAGE

my $doc = <<ENDDOC;
-------------------------------------------------------------------------------
-help          Get help with the script syntax (this text actually).
 
-allvobs       Required, unless a single vobtag is specifed. Defualt usage 
               scenario which causes $_packagefile to traverse all visibel 
               project-vobs and process all baselines in each of them.
               Can't be used with -vob or -component
                
-vob VOBTAG    Single-vob vob mode, process only baselines in the named p-vob
               Can't be used with -allvobs or -component
               
-component COMPONENT-IDENTIFIER
               Single Component mode, process all baselines in the named 
               component, must be given as a fully qualied component-identifier
               like this: component:somecomp\@\\vobtag   
               Can't be used with -allvobs or -vob  

------------------------------------------------------------------------------- 
ENDDOC

################################ M A I N ######################################
### Global variables ###
my ( $log, $pccobj, $t_begin, @comps, @pvobs, %options, $incremental_pattern, $counter, $t_elapsed );

# Switch specific variables
my ( $sw_help, $sw_verbose, $sw_debug, $sw_allvobs, $sw_vob, $sw_component );
$incremental_pattern = "Incrementally Labeled";
$counter             = 1;                         #

# Ensure each output line is printed immediately
$| = 1;

# Get reference to Praqma ClearCase object
die "Couldn't get reference to module from package scriptlog.pm " unless $log = scriptlog->new();
die "Couldn't get reference to module from package pcc.pm " unless $pccobj = pcc->new( logobject => \$log );

intialize();

foreach (@comps) {
  $log->information("Processing component number $counter ($_ )\n");

  my @baselines = $pccobj->ct( command => "lsbl -fmt " . '%Xn,[%[label_status]p]\n' . " -component $_" );
  $sw_debug && $log->information( "Found these baselines in component $_:\n" . join( '', @baselines ) );

  my @incrementally = get_incrementally( \@baselines );
  $sw_debug && $log->information( "Found these incrementaly labelled baselines:\n" . join( '', @baselines ) );

  $log->information("Upgrading incrementally baselines in component $_\n");
  upgrade_bl( \@incrementally );

  $counter++;
}

$t_elapsed = time() - $t_begin;
$log->information("Elapsed time (sec): $t_elapsed\n");

#################################  S U B S   ##################################

sub upgrade_bl {
  # Expects arrayreference to list of fully qualifed baselines that 
  # should be upraded
  
  my $arrayref = shift;
  foreach (@$arrayref) {
    $pccobj->ct( command => 'chbl -full ' . $_ );

  }
}

sub get_incrementally {
  # Expects arrayreference to list of fully qualifed components that 
  # should be searched for incrementally labelled baselines
  # Returns array of those found

  my $arrayref = shift;
  my @result;
  foreach (@$arrayref) {

    # each looks like  'baseline:deliverbl.mhaa_PDS316_PenSoftware.20110825.123354@\PDS_PVOB,[Incrementally Labeled]'
    if (m/$incremental_pattern/i) {
      ( my $bl = $_ ) =~ s/(\S+)(,\[.*)/$1/;
      push @result, $bl;
    }
  }
  chomp @result;
  return @result;
}

sub validate_options {
  # Check input paramteres
  
  %options = (
    "help"        => \$sw_help,
    "debug!"      => \$sw_debug,
    "verbose!"    => \$sw_verbose,
    "allvobs!"    => \$sw_allvobs,
    "vob=s"       => \$sw_vob,
    "component=s" => \$sw_component

  );

  die "$usage" unless GetOptions(%options);

  if ($sw_debug) {
    print "Debug mode on\n";
  }

  my $exitmessage;

  #  help required
  $exitmessage = "Required option missing:\n";
  unless ( $sw_allvobs or $sw_vob or $sw_component ) {
    $sw_help = 1;
    print "$exitmessage";
  }

  #  help requested
  $exitmessage = "$header\n$revision\n$usage\n";
  if ($sw_help) {
    print "$exitmessage";
    exit 0;
  }

  $exitmessage = "Can't use -component or -vob with -allvobs\n\n$usage\n";
  if ( $sw_allvobs and ( $sw_vob or $sw_component ) ) {
    die "$exitmessage";
  }

  $exitmessage = "Can't use both -component and -vob together\n\n$usage\n";
  if ( $sw_vob and $sw_component ) {
    die "$exitmessage";
  }

}    # end sub

sub intialize() {
  # Initalize world
  
  $log->enable(1);
  $log->set_verbose(1);

  # Store start time
  $t_begin = time();

  validate_options();

  # Set list of components to process
  if ($sw_component) {
    push @comps, $sw_component;
    $sw_debug && $log->information( "Single component mode execution selected the following" . join( '', @comps ) );
  }
  elsif ($sw_vob) {

    # list components in specified vob
    @comps = @{ $pccobj->get_components_invob( 'pvob' => $sw_vob ) };
    $sw_debug && $log->information( "Single vob mode execution selected the following" . join( '', @comps ) );
  }
  else {

    # list components in all pvob
    foreach ( @{ $pccobj->get_pvobs() } ) {
      push @comps, @{ $pccobj->get_components_invob( 'pvob' => $_ ) };
    }
    $sw_debug && $log->information( "All vobs mode execution selected the following" . join( '', @comps ) );
  }

  $log->information( "Processing " . scalar(@comps) . " components\n" );

}    # end sub

###############################################################################

=pod

=head1 Description

This script will upgrade incrementally labelled baselines to full. 


=head1 Synopsis

By default ClearCase will only label newly created baselines incrementally, that 
means only affected version are labelled, because a full labelling takes more time
than the user is willing to spend while waiting for the new baseline to be created.
But incrementally labelled baselines are not useable for recommandation or inter-
project deliveries, so you will have to upgrade the labelling to "full" before 
proceeding with recommandation or interproject deliver. 

This script is meant to adress that. The default usage scenario is to have it 
executed nightly (the -allvobs switch)

In -allvobs mode, all UCM project vobs are found, and in each project vob, all
components are found. Then all baselines of each component is queried for its 
label status, and if the label status is incrementally labelled, we will upgrade it
to full.

The script can also be run in single vob mode, where a vobtag is given as parameter to
the script, then only the compenents of that vob are processed.

Finally the script are capable of processing a single component


=head2 Requirements

A couple for perl modules are needed:

praqma::pcc
praqma::scriptlog
File::Basename
Getopt::Long

=head2 Examples

Allvobs mode:

ratlperl I<full_path_to_script> -allvobs

Single Vob mode:

ratlperl I<full_path_to_script> -vob I<vobtag>

Single Component mode:

ratlperl I<full_path_to_script> -component I<fully qualifed component selector>



=cut
