
require 5.000;
use strict;
$| = 1;
our ( $Scriptdir, $Scriptfile );

BEGIN {
    use File::Basename;
    use  File::Spec;
    $Scriptdir  = dirname(__FILE__) . "\\";
    $Scriptfile = basename(__FILE__);
    $Scriptdir  = File::Spec->canonpath("$ENV{CCUTILS}");
}

# DEBUG != 0
# * doesn't go through all the vobs but instead just searches in one or a few (hard code in code below)
# * prints additional debugging info
#my $DEBUG = 1;
my $DEBUG = 0;
# NO_EMAIL != 0
# * disables sending of email
#my $NO_EMAIL = 1;
my $NO_EMAIL = 0;

# Use clauses
use File::Basename;
use File::Temp;
use Getopt::Long;
use Cwd;

#if ($DEBUG) {
#  # To be able to test run the script outside of dkclearp11 ccutil dir
#  $Scriptdir = '\\dkclearp11\ccutils\Praqma'; # unless $Scriptdir;
#  use lib "$Scriptdir\praqma";
#} else {
  use lib "$Scriptdir\\praqma";
#}
use scriptlog;
use pcc 0.1011;

my $log       = scriptlog->new;
my $pccObject = pcc->new;

my $grace= 80;
my @findings;
my %culprits;
my $workview = "A901599_view";
my $viewroot = "M:\\$workview";
my $bodyfile = "mailbody.txt";
my $sender = 'flemmingsorensen@grundfos.com';
my $adminemail = 'flemmingsorensen@grundfos.com';

qx(cleartool startview $workview);

$log->enable(1);
$log->set_verbose(1);

# get all the vobtags
my @vobtags;
if ($DEBUG) {
  @vobtags = qw(\_TEST \ctrleTAP_BUILD);
} else {
  @vobtags = @{ $pccObject->get_vobtags() };
}

foreach (@vobtags) {
    my $vobtag = $_;
    print "Checking for old checkouts in $vobtag \n" if ($DEBUG);
	$pccObject->ct( command => "mount $_" , err_ok => 1);
	my $cmd = "lsco -all -fmt \%u\\t\%Ad\\t\%TUf\\t\%En\\n $viewroot$_";
	# $log->information ( "Will execute:  $cmd");
	my @checkouts = $pccObject->ct( command => $cmd, err_ok => 1 );
    my @checkouts_with_vobtag;
    foreach (@checkouts) {
	  chomp;
	  push @checkouts_with_vobtag, "$_\t$vobtag\n";
	}
	push @findings, @checkouts_with_vobtag;
	# $log->information ("Found " . scalar(@checkouts) .  " checkout in $_"); 
	$pccObject->ct( command => "umount $_" , err_ok => 1);
}

chomp(@findings);

foreach my $record (@findings) {
	# $log->information ("Splitting string $record\n");
	my ($user,$age,$viewuuid, $checkout, $vobtag);
	($user,$age,$viewuuid, $checkout, $vobtag ) = split (/\t/,$record,5);
	next if (!$age && !$viewuuid && !$checkout && !$vobtag);
	$checkout =~ s/\Q$viewroot//;
	if ($age > $grace) {
		#$log->warning("Found user $user having checkout for $age days in view $viewuuid of File: $checkout\n");
		my $tag = getviewtag(uuid => $viewuuid );
        my $viewtag = $tag ? ($tag) : $viewuuid;
        if ($tag !~ /Error: No matching entries found for uuid/) {
		  # view tag exists
		  chomp $tag;
		  my $email = $user . '@grundfos.com' ;
		  my $message = "Checked out for $age days in view $tag:\n$checkout\n\n";
                  if (!$NO_EMAIL) {
		    print "Info sent to: $email\n$message\n\n";
                  } else {
		    print "Info, not sent since NO_EMAIL!=0: $email\n$message\n\n";
                  }
		  push @{$culprits{$email}}, $message; 
		} else {
		  # view tag doesn't exist. then we should email admin it from registry
		  my $cmd = "cleartool rmview -force -vob $vobtag -uuid $viewuuid";
		  my $message = "Checked out for $age days and no view tag for: $checkout\nRemove all checkouts in the vob, from this view, by running the command:\n$cmd\n\n";
                  if (!$NO_EMAIL) {
		    print "Info sent to: $adminemail\n$message\n\n";
                  } else {
		    print "Info, not sent since NO_EMAIL!=0: $adminemail\n$message\n\n";
                  }
		  push @{$culprits{$adminemail}}, $message;
		}
	}
}

foreach my $reciep (sort keys %culprits) {
	unlink $bodyfile;
	open BODY, "> $bodyfile";
	print BODY "These versions have been checked out for more than $grace days\n";
	print BODY "You should not have checkouts for more than a couple of days.\n"; 
	print BODY "Please either check them in, undo the checkout or delete the view.\n"; 
	print BODY "If you need assistance please contact your ClearCase administrator\n\n";

	foreach my $version ( sort @{ $culprits{$reciep} } ) {
		print BODY "$version";
	}
	print BODY "\n";
	close BODY;

	my $blatcmd = "$Scriptdir\\Praqma\\Blat\\Blat.exe $bodyfile -to $reciep -subject \"You have old checkouts - please take action\" -f $sender -noh -server message.grundfos.com:2025"; 

	if (!$NO_EMAIL) {
	  qx($blatcmd);
	}
}

qx(cleartool endview -server $workview);

#return $log->get_accumulated_errorlevel();

########################################
sub getviewtag{
    my %parms = @_;
	my $uuid = $parms{uuid};
	return $pccObject->ct( command => 'lsview -s -region * -uuid ' . $uuid, err_ok => 1);
}

