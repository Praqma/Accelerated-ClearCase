# Checks a list of targets to see that they were built with all changed
# elements in a delivery activity.
#
# Written by David Baird <david.baird@homemailNOSPAM.com>
#
# Install like this:
#
#   ct mktrtype -ucmobject -all -postop deliver_complete \
#       -c 'Validate all target derived objects were built' \
#       -execunix 'perl {unix_trigger_path}/ucm_check_targets.pl' \
#       -execwin  'perl {windows_trigger_path}\\ucm_check_targets.pl' \
#       UCM_CHECK_TARGETS@{pvob_tag}
#
#   ct mkattype -vtype string -nc check_targets

die "The script $0 is not ready for deployment\n";

# web views and snapshot views don't have derived objects
exit 0 if $ENV{CLEARCASE_VIEW_KIND} =~ /snapshot/;

# values from trigger environment
my $op_kind = $ENV{CLEARCASE_OP_KIND};
my $istream = $ENV{CLEARCASE_STREAM};
my $viewtag = $ENV{CLEARCASE_VIEW_TAG};
my $hostos  = $ENV{OS};

# pvob from istream name
my ($pvob) = ($istream =~ m{\@(.+)$});

# get the check_targets attribute
my ($check_targets) = split '"', qx{cleartool describe -short -aattr check_targets stream:$istream};
exit 0 if not $check_targets;

my (%changeset, %dolist, $error);

# Enter the view directory, handled differently for
# Windows and Unix. Note the following assumptions:
# on Windows, the view path is in the M: drive
# on Unix, all VOBs are mounted through /vobs
if ($hostos eq 'Windows_NT') {
    my $viewpath = "m:\\$viewtag";
    chdir $viewpath;
    $viewpath =~ tr{/}{\\};
}
else {
    my $viewpath = "/view/$viewtag";
    chdir "$viewpath/vobs";
}

# allow for a file which lists the targets to check
if ($check_targets =~ /^\@/) {
    my $file = $check_targets;
    for ($file) { s/^\@//; tr{\\}{/}; }
    local *FH;
    open FH, "<.$file" or do {
        system qw{clearprompt proceed -mask proceed -default proceed -prompt}, qq{"Can't open target list file: $file: $!"};
        exit 1;
    };
    local $/;
    ($check_targets = <FH>) =~ tr/\n/ /;
    close FH;
}

# now look at all the targets, and first make sure it
# actually exists as a derived object
for ($check_targets) { tr{\\}{/}; s{(^|\s)/}{$1./}g; }
foreach (split ' ', $check_targets) {
    my $file = $_;
    next if $file eq '';
    my ($pwd) = map { chomp; $_ } qx{cleartool pwd};
    my ($ls)  = map { chomp; $_ } qx{cleartool ls "$file"};
    next if $ls =~ /\@\@\d\d-\w\w\w(-\d\d)?\.\d\d:\d\d\.\d+$/;
    $error = $file;
}

if ($error eq '') {
    local *PIPE;

    # collect list of elements in the change set of the delivery
    # activity
    open PIPE, "cleartool lsactivity -cview -cact -long |" or exit 0;
    while (<PIPE>) {
        # Today, I would not have written the following code as
        # you see it now. I would have used -M instead of stat, for
        # instance. Feel free to rewrite this and send me your changes.
        /^\s*${viewpath}(.+)\@\@\S+CHECKEDOUT/i and do {
            my $element = $1;
            my $mtime = (stat("${viewpath}$element"))[9];
            my($day,$mon,$date,$time,$year) = split ' ', localtime($mtime);
            $date = sprintf("%02d", $date);
            $year = sprintf("%02d", $year % 100);
            my $mtime_str = "<$date-$mon-$year.$time>";
            $changeset{$element}->{'checkout'} = $mtime_str;
            next;
        };
        /^\s${viewpath}(.+)\@\@(\S+)/i and do {
            $changeset{$1}->{'version'} = $2;
            next;
        };
    }
    close PIPE;

    # collect list of dependancies of the targets in question, only
    # concerned about elements, compare the findings with the change
    # set of the delivery activity, and if any version or timestamp
    # differs, it is an error
    open PIPE, "cleartool catcr -element_only -union $check_targets |" or exit 0;
    while (<PIPE>) {
        last if not %changeset;
        # a version of a checked in element
        /^\s*\d (.+)\@\@(\S+)/ and do {
            my $element = $1;
            my $version = $2;
            next unless exists $changeset{$element};
            if ($version ne $changeset{$element}->{'version'}) {
                $error = $element;
                last;
            }
            delete $changeset{$element};
        };
        # the timestamp of a checked out element
        /^\s*\d (.+)(\<.+\>)/ and do {
            my $element = $1;
            my $date = $2;
            $element =~ s/\s+$//;
            next unless exists $changeset{$element};
            if ($date ne $changeset{$element}->{'checkout'}) {
                $error = $element;
                last;
            }
            delete $changeset{$element};
        };
    }
    close PIPE;
}

# no problems, normal exit
exit 0 if ($error eq '');

my ($return, $prompt);

# inform the user of the element found not included in the config
# record of the target in question
if (index($check_targets, $error) != -1) {
    $error =~ s/^\.//;
    $prompt = "Warning: The target '$error' \n" .
              "was not built with clearmake. \n" .
              "Do you want to continue with the delivery completion?";
}
else {
    $prompt = "Warning: Not all targets have been built with clearmake. \n" .
              "The element '$error' was \n" .
              "not included in a required target file. \n" .
              "Do you want to continue with the delivery completion?";
}

# the user can either cancel the delivery or continue
if (length($ENV{'CLEARCASE_CMDLINE'}) == 0) {
    $return = system(qw{clearprompt yes_no -mask}, 'yes,no', qw{-default no -prompt}, qq{"$prompt"}) & 0xffff;
}
else {
    print "$prompt  [no] "; $retval = <STDIN>;
    $return = $retval =~ m/^y(es)?$/i ? 0 : 1;
}

# exit according to the user's response
exit $return;

