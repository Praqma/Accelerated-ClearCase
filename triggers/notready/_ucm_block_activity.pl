# Prevents developers from creating non-delivery and non-rebase activities
# on integration streams, and from reusing delivery and rebase activities.
# Also a better implementation of read only streams.
#
# Written by David Baird <david.baird@homemailNOSPAM.com>
#
# Install like this (for Unix like systems):
#
#   ct  mktrtype -ucmobject -all -preop mkactivity,setactivity \
#       -c "Restricted usage of delivery and rebase activities" \
#       -execunix 'perl {unix_trigger_path}/ucm_block_activity.pl' \
#       -execwin  'perl {windows_trigger_path}\\ucm_block_activity.pl' \
#       UCM_BLOCK_ACTIVITY@{pvob_tag}
#
#   ct mkattype -vtype string -nc integrators@{pvob_tag}
#   ct mkattype -vtype integer -default 1 -nc unblocked@{pvob_tag}
#   ct mkattype -vtype integer -default 1 -nc readonly@{pvob_tag}
#
# Allow integrators to make and reuse activities like this:
#
#   ct mkattr integrators '"dbaird ccadmin"' stream:{integration_stream}@{pvob_tag}
#
# Disable this trigger for a single stream like this:
#
#   ct mkattr -default unblocked stream:{integration_stream}@{pvob_tag}
#
# Make a stream read-only
#
#   ct mkattr -default readonly stream:{integration_stream}@{pvob_tag}
#

die "The script $0 is not ready for deployment\n";

# values from trigger environment
my $parent_op_kind = $ENV{CLEARCASE_POP_KIND};
my $op_kind        = $ENV{CLEARCASE_OP_KIND};
my $project        = $ENV{CLEARCASE_PROJECT};
my $stream         = $ENV{CLEARCASE_STREAM};
my $user           = $ENV{CLEARCASE_USER};
my $activity       = $ENV{CLEARCASE_ACTIVITY};

# extract pvob from project name
(my $pvob = $project) =~ s/.*\@//;

# error if on a read only stream and not a rebase activity
my $readonly = qx{cleartool describe -short -aattr readonly stream:$stream};
error_exit("Activity creation in read only streams is prohibited.")
    if $readonly == 1 and $parent_op_kind ne 'rebase_start';

# integrators get to do anything
my $integrators = qx{cleartool describe -short -aattr integrators stream:$stream};
$integrators =~ tr{"\n}{}d;
# this is a case insensitive match
exit 0 if grep { $_ eq lc($user) } split ' ', lc($integrators);

# exit if in the middle of a rebase or delivery
for (qw{deliver rebase}) { exit 0 if $parent_op_kind eq "${_}_start" }

# exit if this an unblocked stream
my $unblocked = qx{cleartool describe -short -aattr unblocked stream:$stream};
exit 0 if $unblocked == 1;

# error trying to reuse a deliver or rebase activity
error_exit("Reusing a $1 activity is prohibited.")
    if $activity =~ /(deliver|rebase)\.[^.]+\.\d+\.\d+/ and $op_kind eq 'setactivity';

# error if the current stream is the integration stream
my ($istream) = split '\n', qx{cleartool lsproject -fmt "%[istream]p" $project};
error_exit("Activity creation in integration streams is prohibited.")
    if "$istream\@$pvob" eq $stream and $op_kind eq 'mkactivity';

# normal exit
exit 0;

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

