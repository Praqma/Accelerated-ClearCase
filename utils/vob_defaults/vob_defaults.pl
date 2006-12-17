require 5.000;
use strict;

#Getting the script dir
our ( $Scriptdir, $Scriptfile );

BEGIN {
	if ( __FILE__ =~ /(.*[\/\\])(.*)$/ ) {
		$Scriptdir  = $1;
		$Scriptfile = $2;
	}
	else {
		$Scriptdir  = "";
		$Scriptfile = __FILE__;
	}
}

use File::Basename;
use lib "$Scriptdir..//..";
use praqma::scriptlog;
use praqma::trigger_helper;
use praqma::acc;

chdir $ENV{SYSTEMDRIVE};

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;

# Initiate logging.
our $log = scriptlog->new;

#Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->enable(1);

# $log->set_verbose(1);
our $logfile = $log->get_logfile();
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.

my %bl_defaults = ();
push @{ $bl_defaults{acc::VOBTYPE_PVOB} },       ("ACC_PRE_SETACT");
push @{ $bl_defaults{acc::VOBTYPE_BCC_CLIENT} }, ("");
push @{ $bl_defaults{acc::VOBTYPE_UCM_CLIENT} }, ("");
push @{ $bl_defaults{acc::VOBTYPE_ADMINVOB} },   ("");

my @vobs = sort qx("cleartool lsvob -s  2>&1");
chomp @vobs;
my $replace = "";
foreach my $vobtag (@vobs) {
	$log->information_always("Checking vob $_");
	$replace = "";
	my @defaultlist  = ();
	my @current_list = get_blacklist($vobtag);
	my @vobtypes     = acc::get_vobtypes($vobtag);
	foreach (@vobtypes) {

		push @defaultlist, @{ $bl_defaults{$_} };    # if ( scalar( @{ $bl_defaults{$_} } ) );

	}

	my %entries = ();
	foreach ( @current_list, @defaultlist ) {
		$entries{$_}++ unless $entries{$_};
	}
	my $oldvalue = join( ',', @current_list );
	my $newvalue = join( ',', sort keys %entries );

	# Update attribute value if changed
	if ( $oldvalue ne $newvalue ) {

		# cleartool mkattr -nc ACC_TriggerBlacklist \"dims,ognoget\" vob:\jbrplay
		my $cmd = "cleartool mkattr $replace -nc " . acc::ATTYPE_TRIGGER_BLACKLIST . ' \"' . $newvalue . '\" ' . "vob:$vobtag 2>&1";

		# create or replace attribute.
		my @retval = qx($cmd);
		if ($?) {
			$log->error( join( '\n', @retval ) );
		}
		else {
			$log->information( join( '\n', @retval ) );
		}
	}

}

sub get_triggernames {

	# Open all trigger script files in the triggers directory.
	# Each of then contains a variable called $TRIGGERNAME

	my ($root, %trnames, @files);
	# Build path to "triggers" directory from here
	($root = $Scriptdir ) =~ s/(.*)(\/.*\/.*\/)$/$1\/triggers/;
	opendir( DIR, $root );
	@files = grep { /\.pl$/i } readdir(DIR);
	closedir(DIR);

	# read each script capture value of $TRIGGERNAME 
	foreach (@files) {
	
		no strict;
		our $TRIGGER_NAME;
		do "$root/$_";
		$trnames{$TRIGGER_NAME} = "$root/$_";
	}
	return %trnames;
}

sub get_blacklist {

	# return sorted array of attribute list values
	my $sw_vob = shift;

	my $cmd               = ' cleartool describe -fmt %SN[' . acc::ATTYPE_TRIGGER_BLACKLIST . "]a vob:$sw_vob  2>&1";
	my $raw_triggerblattr = qx($cmd);
	$? && die "Execution of: [$cmd] failed\n";    # assert success
	chomp($raw_triggerblattr);
	if ( $raw_triggerblattr =~ s/\"//g ) {

		# Attribute exists already, maybe even with empty value
		$replace = "-replace";
	}

	# $raw_triggerblattr =~ s/\"//g;    # get rid of the ' required ' quotes in CC string attributes
	my @blacklist = sort split( ', ', $raw_triggerblattr );    # make a list;
	return @blacklist

}
