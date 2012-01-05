# This is a shopping list of operations upon completion of a delivery
# or rebase in an integration stream. All operations are enabled by
# attributes on the integration stream
#
# 1. Check for attribute "auto_baseline_name" to create a baseline
# automatically. The format of the value must be one of:
#   BASELINE_xxx    ex: BL.11.22_xxx
#   BASELINE*_xxx   ex: BL.11.*_xxx
#   BASELINE.xxx    ex: BL.11.22.xxx
#   BASELINE*.xxx   ex: BL.11.*.xxx
# The number of x's allowed is variable, but it must be at the end
# of the baseline pattern and preceeded by an underline (_) or a
# period (.).
#
# The purpose of the star (*) is to allow a numberic value as
# part of the pattern, which may vary. This allows a sequence
# for example of BL.11.01_001, BL.11.01_002, BL.11.01_003,... Then
# you manually place a new baseline BL.11.02_000, and the sequence
# continues with BL.11.02_001, BL.11.02_002, BL.11.02_003,...
#
# You must place a first baseline on the integration stream, for
# example, BL.11.22_000
#
# 2. Check for attribute "auto_baseline_email" to send an email
# report to the specified email address. This depends on a baseline
# being automatically generated. Multiple address must be separated
# by commas.
#
# 3. Check for attribute "auto_baseline_diff" to attach a difference
# report of changed directories and text files to the automated
# email message.
#
# 4. Check for attribute "deliver_to_stream" and start a delivery of
# the new baseline to a different integration stream. This can be
# from a child integration stream to a project level integration stream
# or to another project's integration streams.
#
# Written by David Baird <david.baird@homemailNOSPAM.com>
#
# Install like this:
#
#   ct mktrtype -ucmobject -all -postop deliver_complete,rebase_complete \
#       -c "Automated operations after delivery or rebase completion" \
#       -execunix 'perl {unix_trigger_path}/ucm_complete_delivery.pl' \
#       -execwin  'perl {windows_trigger_path}\\ucm_complete_delivery.pl' \
#       UCM_COMPLETE_DELIVERY
#
#   ct mkattype -vtype string -nc auto_baseline_name@{pvob_tag}
#   ct mkattype -vtype string -nc auto_baseline_email@{pvob_tag}
#   ct mkattype -vtype string -nc deliver_to_stream@{pvob_tag}
#   ct mkattype -vtype integer -default 1 -nc auto_baseline_diff@{pvob_tag}

die "The script $0 is not ready for deployment\n";


# The following modules is required for the send_baseline_email()
# subroutine.
use MIME::Lite;
# Name of mail host
my $mailhost = 'mailhost';
# Domain of users
my $maildomain = '@mydomain.com';

# The following modules are required for the make_diff() subroutine.
use File::Spec;
use File::Temp;
use ClearCase::Argv;

# values from trigger environment
my $op_kind  = $ENV{CLEARCASE_OP_KIND};
my $project  = $ENV{CLEARCASE_PROJECT};
my $istream  = $ENV{CLEARCASE_STREAM};
my $viewtag  = $ENV{CLEARCASE_VIEW_TAG};
my $user     = $ENV{CLEARCASE_USER};
my $activity = $ENV{CLEARCASE_ACTIVITY};

# the project vob and feature level
my ($pvob) = ($project =~ m/\@(.+)$/);
my $feature_level = qx{cleartool describe -short -aattr FeatureLevel vob:$pvob};

# get the baseline attribute
my $baseline_pattern = qx{cleartool describe -short -aattr auto_baseline_name stream:$istream};
$baseline_pattern =~ tr{"\n}{}d;
exit 0 if $baseline_pattern eq '';

# establish grep patterns
my ($baseline_grep, $tail_grep, $sep, $exes) = ($baseline_pattern =~ /(.*?)(([._](?=x))?(x+))/);
my $precision  = length($exes);
for ($baseline_grep) { s/\./\\./g; s/\*/\\d*/g; }
for ($tail_grep)     { s/\./\\./g; s/x/\\d/g;   }

# get the last baseline
my ($baseline_name) = my @baselines = reverse sort grep /^($baseline_grep)($tail_grep)/o, qx{cleartool lsbl -fmt "%[title]p\\n" -stream $istream};
while (grep /^$baseline_name$/, @baselines) {
    my ($new_number) = ($baseline_name =~ /($tail_grep)/);
    $new_number =~ s/[._]?(\d+)/$1 + 1/e;
    ($baseline_name = $baseline_pattern) =~ s/([._](?=x))?x+/$1 . sprintf("%0${precision}u", $new_number)/e;
}

# prompt the user about the new baseline
my $prompt = "A new baseline will be created, '$baseline_name'. Please be patient.";
if (length($ENV{CLEARCASE_CMDLINE}) == 0 and $ENV{ATRIA_WEB_GUI} != 1) {
    system qw{clearprompt proceed -mask proceed -type ok -default proceed -prompt}, qq{"$prompt"};
}
else {
    print $prompt . "\n";
}

# when running for a web view, then use a ccadmin_{istream} view
($viewtag = $istream) =~ s/(.+)\@.+/ccadmin_$1/ if $ENV{ATRIA_WEB_GUI} == 1;

# the commands are best run in the integration view context
system "cleartool startview $viewtag 2>&1";
my $viewdir = $ENV{OS} eq 'Windows_NT' ? "m:/$viewtag" : "/view/$viewtag";
chdir $viewdir;

# create and promote the new baseline
system qw{cleartool mkbl -c}, qq{"automatically created for '$activity'"}, '-view', $viewtag, $baseline_name;
system qw{cleartool chstream -recommended -default}, $istream if $feature_level > 2;

# the following operations, email notification and deliver baseline to another
# project stream, require a feature level 3 or above PVOB.
exit 0 if $feature_level < 3;

# get the auto_baseline_email attribute
my $baseline_email = qx{cleartool describe -short -aattr auto_baseline_email stream:$istream};
$baseline_email =~ tr{"\n}{}d;
send_baseline_email($baseline_email) if $baseline_email;

# get the deliver_to_stream attribute
my $deliver_to_stream = qx{cleartool describe -short -aattr deliver_to_stream stream:$istream};
$deliver_to_stream =~ tr{"\n}{}d;
run_deliver_to_stream($deliver_to_stream) if $deliver_to_stream;

exit 0;

# subroutine to send baseline email
sub send_baseline_email {
   my $baseline_email = shift;
   
   # get the contributing activities and change set from delivery or
   # rebase activity
   my $contrib_titles = join "\n",
           sort map { my ($a) = qx{cleartool lsact -fmt "%[title]p" $_\@$pvob};
                      $_ = $a if $a ; $_ }
           grep { ! /^rebase\./ }
           map { s/(^")|("$)|\n//g; $_ }
           qx{cleartool lsactivity -contrib $activity};
   $contrib_titles = 'Rebase' if not $contrib_titles;
   
   my ($branch_name) = ($istream =~ /(.+)\@/);
   my $change_set = join "\n",
           sort map { / {4}(m:\\[^\\]+|.+\/vobs)?(.+)\@\@/i; $_ = $2 }
           grep { /$branch_name[\/\\][0-9]+$/o }
           qx{cleartool lsactivity -long $activity};
   
   my ($source_stream) = ($activity =~ /[^.]+\.([^.]+)/);
   
   my $msg = MIME::Lite->new(
      From     => lc($user) . $maildomain,
      To       => $baseline_email,
      Subject  => "New baseline created: $baseline_name",
      Data     =>
         "The new baseline '$baseline_name' was created by $user.\n\n" .
         "Source stream: $source_stream\n\n" .
         "Contributing activities:\n" .
         $contrib_titles .
         "\n\n" .
         "Changed elements:\n" .
         $change_set .
         "\n\n"
   );
   
   my $baseline_diff = qx{cleartool describe -short -aattr auto_baseline_diff stream:$istream};
   my $diff_file;
   if ($baseline_diff == 1) {
      $diff_file = make_diff(split ' ', $change_set);
      $msg->attach(
         Type     => 'TEXT',
         Path     => "$diff_file",
         Filename => 'changeset_diff_report.txt',
         Disposition => 'attachment'
      );
      $msg->scrub(['content-transfer-encoding', 'content-length']);
   }
   
   if ($msg->send('smtp', $mailhost)) {
       # prompt the user about the email
       $prompt = "E-mail notification sent to $baseline_email about new baseline, '$baseline_name'.";
       if (length($ENV{'CLEARCASE_CMDLINE'}) == 0 and $ENV{ATRIA_WEB_GUI} != 1) {
           system qw/clearprompt proceed -mask proceed -type ok -default proceed -prompt/, qq{"$prompt"};
       }
       else {
           print $prompt . "\n";
       }
   }
   else {
       print "MIME::Lite email error\n";
   }
}

# subrouting to run the delivery to a different stream
sub run_deliver_to_stream {
   my $deliver_to_stream = shift;
   
   # can't start delivery of baseline in web interface
   return if $ENV{ATRIA_WEB_GUI} == 1;

   if (length($ENV{CLEARCASE_CMDLINE}) == 0) {
       if ($ENV{OS} eq 'Windows_NT') {
           system qw{clearmrgman /deliver /del_bls}, "stream:$istream", '/target', "stream:$deliver_to_stream\@$pvob";
       }
       else {
           system qw{clearmrgman -deliver -baseline -stream}, "stream:$istream", '-target', "stream:$deliver_to_stream\@$pvob";
       }
   }
   else {
       system qw{cleartool deliver -stream}, "stream:$istream", '-target', "$deliver_to_stream\@$pvob", '-baseline', "$baseline_name\@$pvob";
   }
}

# create difference report
sub make_diff {
   my $cc = ClearCase::Argv->new();
   my $width = 164;
   my $limit = 60;

   my %elems;
   ELEM: for my $elem (@_) {
      $elem = '/vobs' . $elem if $^O ne 'MSWin32';
      my $type = $cc->argv('desc', [qw/-fmt %[type]p/], "${viewdir}$elem")->qx();

      $type eq 'directory' and do {
         my @diff = $cc->argv('diff', [qw/-pred -col 102/], "${viewdir}$elem")->qx();
         splice @diff, 0, 4, "changed directory: $elem\n";
         @{$elems{dir}->{$elem}} = (@diff, '=' x $width . "\n\n");
         push @{$elems{dir}->{list}}, $elem;
         next;
      };
      
      # is this a new element?
      (my $branchpat = $istream) =~ s/(.+)\@.+/.main.$1.0/;
      my $pv = $cc->argv('desc', [qw/-fmt %PVn/], "${viewdir}$elem")->qx();
      if ($pv =~ /$branchpat/) {
         push @{$elems{new}}, $elem;
         next;
      }

      $type =~ /^(text_)?file$/ and do {
         my @diff = $cc->argv('diff', [qw/-opt -b -pred -col/, $width], "${viewdir}$elem")->qx();
         splice @diff, 0, 4, "changed text file: $elem\n";
         if (@diff > $limit + 1) {
            my $cutlines = @diff - $limit;
            splice @diff, $limit, $cutlines, "<$limit line limit> $cutlines more lines...\n";
         }
         @{$elems{text}->{$elem}} = (@diff, '=' x $width . "\n\n");
         push @{$elems{text}->{list}}, $elem;
         next;
      };

      push @{$elems{bin}}, "changed binary file: $elem\n";
   }

   my $fh = new File::Temp(
      TEMPLATE => 'changeset_diff_report.XXXX',
      DIR => File::Spec->tmpdir(),
      SUFFIX => '.txt',
      UNLINK => 1
   );

   print $fh @{$elems{dir}->{$_}} for @{$elems{dir}->{list}};
   print $fh @{$elems{text}->{$_}} for @{$elems{text}->{list}};
   print $fh $_ for @{$elems{bin}};
   print $fh '=' x $width;
   close $fh;

   return $fh;
}

