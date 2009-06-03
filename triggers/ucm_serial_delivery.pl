# Implement a development policy that eliminates the confusion that concurrent
# deliveries or rebases can cause developers. Only one developer can deliver to
# an integration stream at a time.
#
# Written by David Baird <david.baird@homemailNOSPAM.com>
#
# Install like this:
#
#   ct mktrtype -ucmobject -all -preop deliver_start,rebase_start \
#       -c "Only allow serial deliveries and rebases on integration stream" \
#       -execunix 'perl {unix_trigger_path}/ucm_serial_delivery.pl' \
#       -execwin  'perl {windows_trigger_path}\\ucm_serial_delivery.pl' \
#       UCM_SERIAL_DELIVERY@{pvob_tag}
#

# values from trigger environment
my $project    = $ENV{CLEARCASE_PROJECT};
my $stream     = $ENV{CLEARCASE_STREAM};
my $src_stream = $ENV{CLEARCASE_SRC_STREAM};

# pvob from project name
my ($pvob) = ($project =~ m{\@(.+)$});

# do not permit a delivery from a development stream to another project's
# integration stream
my ($src_proj) = split '\n', qx{cleartool lsstream -fmt "%[project]p" $src_stream};
if ($project ne "$src_proj\@$pvob") {
    my ($istream, $src_istream) = split '\n', qx{cleartool lsproject -fmt "%[istream]p\\n" $project $src_proj\@$pvob};
    error_exit("Interproject deliveries from development streams to an integation stream are not permitted")
        if $src_stream ne "$src_istream\@$pvob" and $stream eq "$istream\@$pvob";
}

# first look for a rebase operation in the integration stream
my $rebase = qx{cleartool rebase -status -stream $stream};
my $baseline = ($rebase =~ /\s+baseline:(.+)\@/);
error_exit("A rebase is already in progress from '$baseline'. Please try again later.")
    if $rebase !~ /No rebase in progress/;

# regex to find deliver activity
my $rx = 'deliver\.([^.]+)\.';

# get the last activity, and if it is a delivery, get the development stream
my @activities = map { chomp; $_ } grep { /^$rx/o }
    qx{cleartool lsactivity -short -in $stream};

# look at the three last delivery activities
for (my $i = 0; scalar(@activities - $i) and $i < 3; $i++) {
    my $activity = $activities[$#activities - $i];
    # get status of stream which originated the activity
    my ($ostream) = ($activity =~ /$rx/o);
    my $delivery = qx{cleartool deliver -status -stream $ostream\@$pvob};
    # if the activity name is in the status, then the delivery
    # is in progress
    error_exit("A deliver is already in progress from '$ostream'. Please try again later.")
        if $delivery =~ /$activity/;
}

# no deliver or rebase found, normal exit
exit 0;

# notify the user of the error and stop the operation
sub error_exit {
    my $prompt = shift;
    # trigger vob name project name
    my ($trigvob) = ($project =~ m{([^/\\]+)$});

    if (length($ENV{CLEARCASE_CMDLINE}) != 0 and $ENV{ATRIA_WEB_GUI} == 0) {
        print STDERR "$trigvob trigger: Error: $prompt\n";
    }
    else {
        system qw{clearprompt proceed -mask proceed -type error -default proceed -prompt}, qq{"$prompt"};
    }
    # error exit
    exit 1;
}


