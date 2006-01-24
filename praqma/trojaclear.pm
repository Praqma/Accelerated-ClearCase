#!/usr/local/bin/perl
package trojaclear;

use strict;
use Time::Local;
use Net::Domain qw(hostname hostfqdn hostdomain);
use vars qw($VERSION);

# File version
my $major = 0;
my $minor = 1;
my $build = 10;

die "Versioning failed\n" unless ( $build < 1000 );
our $VERSION = sprintf( "%.4f", $major + ( $minor / 10 ) + ( $build / 10000 ) );

################################################################################

=pod

=head1 NAME

trojaclear.pm is a perl module which can be used with scripts executed by
Praqma's Troja Server.

=head1 SYNOPSIS

In a multisite environment Praqma's Troja Server will have to distribute the command
to execute to the relevant host (most often the host that is mastering the object).

Tha involves looking up the host etc, and it made sense to package theses functions
that will be used repeatedly in a module.

The module is constructed a class.


=head1 DESCRIPTION

Throughout the module reporting depends on an instance of a reference to the scriptlog
 module and the it must have been instantiated las $log in the script that uses
 trojaclear.pm.

For that reason, the constructor "new" will fail if the we can not find $::log

The module is "lazy". It means that means that a get_ method will return the corresponding
property value - if it exist, else it will be calculated.

The remainder of the methods are described below.


=head1 Functions


=cut

# hash for mapping object type to identifier
# Current implemenation of the module only supports label- and branch types, so
# the other ones are outcommented.

our %fqt = (

	#    "replica"   => "replica:",
	"branch" => "brtype:",
	"label"  => "lbtype:",

	#    "trigger"   => "trtype:",
	#    "hyperlink" => "hltype:",
	#    "element"   => "eltype:",
	#    "attribute" => "attype:",

);

sub new {

=head2 new

Create a new instance of the class object

Returns the blessed object reference, if the identifier part maps to one of the
the supported types (see the %fgt in the code).

To get an instance, first make sure that you have use clause for trojaclear and scriptlog:

 use scriptlog;
 use trojaclear;
 my $log=scriptlog->new();
 my $clearobj=trojaclear->new('brtype:some@vob');

Returns:
Object reference if successfull
undef if not.

=cut

	my $class = shift;
	my $obj   = shift;

	# check's if $obj does not have a value,
	# or if there are more values than we can handle
	die "Reference to a scriptlog object called log is required" unless defined $::log;
	return undef if ( !defined($obj) || scalar(@_) );
	my $self = {};
	bless( $self, $class );    # Mark it of the right type
	$self->{InitiallyCreatedWith} = $$obj;

	# Save identifier part of the $$obj, i.e. "brtype:"
	( my $ident = $self->{InitiallyCreatedWith} ) =~ s/(.*:).*/$1/;

	# Check that object is qualified with one of the values from %fqt
	if ( grep { /$ident/ } values %fqt ) {
		$self->{QualifedName} = $self->{InitiallyCreatedWith};    # Ensure Qualified name
		$self->{NAME}         = $self->{QualifedName};
		$::log->information("Object $self->{InitiallyCreatedWith} is accepted, we have an object");
		return $self;                                             # And give it back
	}
	else {
		return undef;                                             #
	}
}

sub get_masterreplica {

=head2 get_masterreplica

Determines the master replica of the object.

To use it you must first have an instance (see "new") then you can do

 my $replica = $clearobj->(get_masterreplica);

which will assign the fully qualified replica name to $replica

Returns undef if the are problems - else it returns that replica name.


=cut

	my $self = shift;
	unless ( defined $self->{MasterReplica} ) {
		my $reply = qx(cleartool des -fmt %[master]p $self->{QualifedName} 2>&1 );
		$self->{MasterReplica} = "replica:$reply";
		if ($?) {
			$::log->assertion_failed("Failed to get Master replica for object [$self->{QualifedName}]:\n$reply");
		}
	}

	return $self->{MasterReplica};
}

sub get_replicaname {

=head2 get_replicaname

Determines the replica name of the vob containing the current object.

To use it you must first have an instance (see "new") then you can do

 my $replica = $clearobj->(get_replicaname);

which will assign the short name to property ReplicaName

Returns undef if the are problems - else it returns that replica name.


=cut

	my $self = shift;
	unless ( defined $self->{ReplicaName} ) {

		( my $vobtag = $self->{QualifedName} ) =~ s/(\S+@)(\S+)$/$2/;    #isolate vobtag
		my $reply = qx(cleartool des -fmt %[replica_name]p vob:$vobtag 2>&1 );
        $self->{ReplicaName} = "replica:$reply\@$vobtag";
		if ($?) {
			$::log->assertion_failed("Unable to determine replica name for vob [$vobtag];\n$reply");
		}
	}

	return $self->{ReplicaName};
}

sub get_replicahost {

=head2 get_replicahost


Determines the host for a replica object.
To use it you must first have an instance (see "new") then you can do

 my $replica = $clearobj->(get_masterreplica);

which will assign the fully qualified replica name to $replica

Returns undef if the are problems - else it returns that host name.

=cut

	my $self = shift;

	# update "MasterReplica" if we need it
	unless ( defined $self->{MasterReplica} ) { $self->get_masterreplica(); }

	# update ReplicaName if we need it
	unless ( defined $self->{ReplicaName} ) { $self->get_replicaname(); }

	unless ( defined $self->{ReplicaHost} ) {

		# Are we at the replica master site ?
		if ( $self->{MasterReplica} eq $self->{ReplicaName} ) {
			$self->{ReplicaHost} = hostfqdn();    #  from Net::Domain
			$::log->information("Mastership is local to current site");
		}
		else {

			# or are we not ?
			my $reply = qx(cleartool des -fmt %[replica_host]p $self->{MasterReplica} 2>&1 );
			chomp $reply;
			if ($?) {
				$::log->assertion_failed("Unable to determine the host for replica [$self->{MasterReplica}];\n$reply");
			}
			else {
				$self->{ReplicaHost} = $reply;
			}
		}
	}

	return $self->{ReplicaHost};
}

sub removetype ($) {

=head2 removetype ($)

Removes a type object from clearcase - use it carefully
It will remove - or attempt to remove the specified type object, but be warned,
removing a type object, will remove any instances to.

If you are removing a branch type object, and it has been used for branching of any
element, any version of that branch are removed as well. For versions they end up in
lost+found, but for for instance label types they is no way back.

=cut

	my $self   = shift;
	my $byuser = shift;

	unless ( defined $self->{Removed} ) {
		my $reply = qx(cleartool rmtype -force -rmall -c " removed by Troja webservice, on request by $byuser" $self->{InitiallyCreatedWith} 2>&1 );
		chomp $reply;
		$self->{Removed} = $reply;
		if ($?) {
			$::log->assertion_failed("Unable remove type [$self->{InitiallyCreatedWith}];\n$reply");
		}
    	$::log->information("$self->{Removed}");
    }

	return $self->{Removed};
}

sub locktype ($) {

=head2 locktype ($)

locks a type.

To use it call

 $clearojb->(locktype)


Returns the locked state on success
Returns undef

=cut

	my $self   = shift;
	my $byuser = shift;

	unless ( defined $self->{Locked} ) {
		my $reply = qx(cleartool lock -c "Locked by $byuser" $self->{InitiallyCreatedWith} 2>&1 );
		chomp $reply;
		$self->{Locked} = $reply;

		if ($?) {
			$::log->assertion_failed("Unable to lock type [$self->{InitiallyCreatedWith}];\n$reply");
		}
		$::log->information("$self->{Locked}");
	}
	return $self->{Locked};
}

sub get_creationdate {

=head2 get_creationdate

Find object creation time, and convert to seconds since epoch.

Returns creation time in seconds since epoch

        $clearojb->(get_creationdate);

Returns undef if we can not determine the creation time.


=cut

	my $self = shift;

	unless ( defined $self->{ObjectCreatedInEpoch} ) {
		$ENV{'CCASE_ISO_DATE_FMT'} = "1";
		my $reply = qx(cleartool des -fmt %Nd $self->{QualifedName} 2>&1 );
		if ($?) {
			$::log->assertion_failed("Failed to get object creation data for [$self->{QualifedName}];\n$reply");
		}
		else {
			# The next couple of conversions are not too pretty, but it works
			my ( $year, $month, $date, $hour, $minute, $second ) = ( $reply =~ /^(\d{4})(\d{2})(\d{2})\.(\d{2})(\d{2})(\d{2})/ );
			# make array, while removing leading zeroes, and remap year and month to values that are consistent with perl's time functions
			my @epoch_creat = split /,/, sprintf( "%d,%d,%d,%d,%d,%d", $second, $minute, $hour, $date, $month - 1, $year - 1900 );
			my $epoch_created = timegm(@epoch_creat);
			$self->{ObjectCreatedInEpoch} = $epoch_created;
		}
	}

	return $self->{ObjectCreatedInEpoch};

}
## private functions

sub DESTROY {

=head2 DESTROY

This is a standard object destructor.
Called automatically on script exit, but here it is, if you want to get rid of
an object instance.


=cut

	my $self = shift;
}

#########################   END OF SUBS  #######################################

=head1 SUPPORT

Visit http://www.praqma.net to get help.

=cut

1;

__END__
