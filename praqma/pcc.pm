package pcc;

use strict;
require Exporter;

our ( $_packagedir, $_packagefile );

BEGIN {
  use File::Basename;
  ( $_packagefile, $_packagedir ) = fileparse(__FILE__);
}

use lib "$_packagedir";
use lib "$_packagedir/..";

#our $VERSION = &$set_version();
# Module version
# set the version for version checking

our $VERSION = 0.02;

use vars qw($VERSION);

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

@ISA         = qw(Exporter);
@EXPORT      = qw(&new &func1 &func2 &func4);
%EXPORT_TAGS = ();

# eg: TAG => [ qw!name1 name2! ],
# your exported package globals go here,
# as well as any optionally exported functions
@EXPORT_OK = qw($Var1 %Hashit &func3);
use vars qw($Var1 %Hashit);

# non-exported package globals go here
use vars qw(@more $stuff);

# initialize package globals, first exported ones
$Var1   = '';
%Hashit = ();

# then the others (which are still accessible as $Some::Module::stuff)
$stuff = '';
@more  = ();

# all file-scoped lexicals must be created before
# the functions below that use them.
# file-private lexicals go here

my $priv_var        = '';
my %secret_hash     = ();
my $get_ct_exit_val = sub {
  return ( scalar($?) / 256 );
};

# make all your functions, whether exported or not;
#######################################################################################
#
my $set_version = sub {

  # File version
  my $major = 0;
  my $minor = 0;
  my $build = 2;
  die "Versioning failed\n" unless ( $build < 1000 );
  sprintf( "%.4f", $major + ( $minor / 10 ) + ( $build / 10000 ) );
};

=head2 pcc->new( )
Creates an object used access object methods and properties
=cut

sub new () {
  my $package = shift;
  my %params  = @_;
  my $self    = {};
  bless( $self, $package );
  return $self;
}

=head2 pccObject->ct(command=> "string", [err_ok => 1] )

Runs cleartool commands, call with named parameters
Required parameters:
  command = the cleartool command and arguments
Optional parameters
  err_ok = if this parameter is passed, we are forgiving if the are errors, meaning $? has non-zero value
           if err_ok is not set it defaults to 0
Depending on the caller context, either list or scalar is returned, it looks for value of wantarray to decide.

=cut

sub ct ($) {
  my $self  = shift;
  my %parms = @_;
  die "input parameter for key 'command' requied" unless ( $parms{command} );

  # unless $parms{err_ok} is set, force it to be zero
  $parms{err_ok} = defined( $parms{err_ok} ) ? $parms{err_ok} : 0;

  my $cmd = 'cleartool ' . $parms{command} . ' 2>&1';
  my @res = qx($cmd);

  # Report errors unless we expect the call to generate non-zero exit value
  unless ( $parms{err_ok} ) {
    if ($?) {
      my $msg =
        "The command [$cmd]\ndidn't return as expected.\nExit value was " . &$get_ct_exit_val() . "\nThe system reply was\n" . join( '', @res );
      die "$msg";
    }
  }
  return ( wantarray ? @res : ( join( '', @res ) ) );
}

=head2 pccObject->get_components_invob(pvob => pvob_tag )

Returns an array reference fully qualified streamsof the visible (current region) vobs

=cut

sub get_components_invob( ) {
  my $self  = shift;
  my %parms = @_;
  die "named parameter 'pvob' requiered!" unless defined( $parms{pvob} );

  my $property = "components_$parms{pvob}";
  my ( @retval, $tagonly );
  return $self->{$property} if defined( $self->{$property} );

  # get components in one vob
  chomp( $parms{pvob} );
  @retval = sort $self->ct( command => 'lscomp -fmt %Xn\n -invob ' . $parms{pvob}, err_ok => "0" );
  chomp(@retval);
  @{ $self->{$property} } = @retval;
  return $self->{$property};

}

=head2 pccObject->get_vobs( )
Returns an array reference of the visible (current region) vobs

=cut

sub get_vobs {
  my $self = shift;
  return $self->{vobs} if defined( $self->{vobs} );

  # find all vobs, return an array of the vobtags
  my @retval = sort $self->ct( command => "lsvob", err_ok => "0" );
  chomp(@retval);
  push @{ $self->{vobs} }, @retval;
  return $self->{vobs};
}

=head2 pccObject->get_pvobs( )
Returns an array reference containing the vobtags of the visible ucm project vobs

=cut

sub get_pvobs {

  my $self = shift;
  return $self->{p_vobs} if defined( $self->{p_vobs} );

  # find all pvobs in vob's list
  my @retval = grep { /(.*ucmvob.*)/ } @{ $self->get_vobs() };
  foreach (@retval) {
    s/(^..)(\S+)(\s+.*$)/$2/;
  }
  chomp(@retval);
  push @{ $self->{p_vobs} }, @retval;
  return $self->{p_vobs}

}

=head2 pcc->DESTROY( )
Destroys the pcc object
=cut

sub DESTROY {
  my $self = shift;

  # printf( "$self self-destroying at %s\n", scalar localtime );

}

########### REMAINING SUBS ARE FROM THE TEMPLATE  - THEY SHALL GO AWAY LATER       ####

# here's a file-private function as a closure,
# callable as &$priv_func.
my $priv_func = sub {

  # stuff goes here.
};

# no prototype
sub func1 {

  return if (1);
}

# proto'd void
sub func2() {

  return if (1);
}

# proto'd to 2 scalars
sub func3($$) {

  return if (1);
}

# this one isn't auto-exported, but could be called!
# proto'd to 1 hash
sub func4(\%) {
  return if (1);
}

# ref END { return if (1); }

1;
