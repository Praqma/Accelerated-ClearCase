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

# Module version

my $major = 0;
my $minor = 1;
my $build = 5;
our $VERSION = &format_version_number( $major, $minor, $build );

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

my $use_scriptlog = 0;    # I can write to the a log created with scriptlog

# make all your functions, whether exported or not;
#######################################################################################
#

=head2 pcc->new( )

 Creates an object used access object methods and properties
 

=cut

sub new {
	my $package = shift;
	my %params  = @_;
	my $self    = {};
	bless( $self, $package );
	if ( defined( $params{logobj} ) ) {
		$self->{logobj} = $params{logobj};
		$use_scriptlog = 1;
	}
	return $self;
}

=head2 pccObject->get_replicahost (vobtag => "vobtag")

Return hostname of replica (vob)

=cut 

sub get_replicahost ($) {

	my $self             = shift;
	my %parms            = @_;
	my $replicashortname = $self->ct( command => "describe -fmt %[replica_name]p vob:$parms{vobtag}" );
	my $replica          = "replica:$replicashortname@" . $parms{vobtag};
	my $replicahost      = $self->ct( command => "describe -fmt %[replica_host]p $replica" );
	return $replicahost;
}

=head2 pccObject->IsReplicated (vobtag => "vobtag")

Check if a vob is replicated.

Return 0 if it not replicated
Return 1 if it is replicated

=cut 

sub IsReplicated ($) {

	my $self  = shift;
	my %parms = @_;
	my $cmd   = 'describe -fmt %[vob_replication]p vob:' . $parms{vobtag};
	if ( grep { /unreplicated/ } $self->ct( command => $cmd ) ) {
		return 0;
	}
	else {
		return 1;
	}
}

=head2 pccObject->IsInProgress (stream => "fully_qualifed_stream, operation => "op" )

Check if a stream is in progress of being rebased or delivering

Requires 2 named parameters:
"stream" must be a fully qualified stream
"operation must either rebase or deliver

Return 0 if no operation is in progress
Return details if rebase or deliver operation is active on stream

=cut

sub IsInProgress ($$) {

	my $self      = shift;
	my %parms     = @_;
	my $operation = lc( $parms{operation} );
	$self->assert_parm( lookfor => "stream",         search_in => $parms{stream} );
	$self->assert_parm( lookfor => "rebase|deliver", search_in => $operation );
	my $reply = $self->ct( command => "$operation -status -stream $parms{stream}" );
	$self->{logobj}->information($reply) if ($use_scriptlog);
	if ( grep { /^No $operation/ } $reply ) {
		return 0;
	}
	else {
		return $reply;
	}

}

=head2 pccObject->get_master_replica( object => "fully_qualifed_object" )

Get the replica name mastering the object

Returns the Name of object's master replica
or
returns 0 if that couldn't be found, and we haven't died already

=cut

sub get_master_replica ($) {

	my $self  = shift;
	my %parms = @_;

	#	$self->assert_parm( lookfor => "object", search_in => $parms{object} );
	my $reply = $self->ct( command => "describe -fmt %[master]p $parms{object}" );
	return ($reply) ? $reply : 0;

}

sub assert_parm {
	my $self      = shift;
	my %parms     = @_;
	my $lookfor   = $parms{lookfor};
	my $search_in = $parms{search_in};

	unless ( $search_in =~ /$lookfor/ ) {

		my $msg = "Incorrect parameters received, expected parameter \"$lookfor\" with a fully qualifed $lookfor name";

		if ($use_scriptlog) {
			$self->{logobj}->assertion_failed($msg);
		}
		else {
			die "$msg\n";
		}

	}

}

=head2 pccObject->get_integration_stream( project => "fully_project" )

Get the integration stream name.

Returns the fully qualified stream name of the project's integrations
or
returns 0 if that couldn't be found, and we haven't died already

=cut

sub get_integration_stream ($) {
	my $self  = shift;
	my %parms = @_;
	$self->assert_parm( lookfor => "project", search_in => $parms{project} );
	my $reply = $self->ct( command => "describe -fmt %[istream]Xp $parms{project}" );
	return ($reply) ? $reply : 0;

}

=head2  pccObject->get_dependants( baseline => "fully_qualified_baseline" )

Returns an array baseline that this baseline depends on 
Returns 0 if there no depending baselines

=cut

sub get_dependants ($) {

	my $self  = shift;
	my %parms = @_;
	die "Incorrect parameters received, expected parameter \"baseline\" with a fully qualifed baseline name"
	  unless ( $parms{baseline} =~ /baseline:\S+\@\S+/ );
	my @reply = split( /, /, $self->ct( command => "describe -fmt %[depends_on]Cp $parms{baseline}" ) );
	if ( scalar(@reply) ) {
		foreach (@reply) {
			$_ = "baseline:$_";
		}

		return @reply;
	}
	else {
		return 0;
	}

}

=head2 pccObject->is_rootless(component=> "fully_qualified_component" )

True if component is a rootless component

returns 1 (as true) if the component is a rootless component
returns 0 (as false) if the component has a root directory

=cut

sub is_rootless ($) {
	my $self  = shift;
	my %parms = @_;
	die "Incorrect parameters received, expected parameter \"component\" with a fully qualifed compoenent name"
	  unless ( $parms{component} =~ /component:\S+\@\S+/ );
	my $reply = $self->ct( command => "des -fmt %[root_dir]p $parms{component}" );
	if ($reply) {

		# is something, so there is a root
		return 0;
	}
	else {
		return 1;
	}

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
	die "named parameter 'pvob' required!" unless defined( $parms{pvob} );

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

=head2 format_version_number (MAJOR,MINOR,BUILD) 
Perl module version numbers useable for instance use or require statements
operates solely on numbers, strings are not useable. This sub converts a 3 level 
version defintion consisting of MAJOR, MINOR and BUILD to a decimal number.


Example:
If MAJOR equals 4, MINOR equals 2 and BUILD equals 16 format will return 
4.2016

Input: 3 numbers, major, minor and build
Returns: Decimal representation of the above following the described rules

=cut 

sub format_version_number ($$$) {

	my $l_major = scalar( $_[0] );
	my $l_minor = scalar( $_[1] );
	my $l_build = scalar( $_[2] );
	die "Versioning failed\n" unless ( $l_build < 1000 );
	return sprintf( "%.4f", $l_major + ( $l_minor / 10 ) + ( $l_build / 10000 ) );
}

=head2 pcc->DESTROY( )
Destroys the pcc object
=cut

sub DESTROY {
	my $self = shift;

	# printf( "$self self-destroying at %s\n", scalar localtime );

}

# Modules must end with:
1;
