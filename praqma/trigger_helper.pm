require 5.001;

package trigger_helper;
use strict;
our ( $scriptdir, $scriptfile );

BEGIN {
    $scriptdir  = ".\\";
    $scriptfile = $0;      # Assume the module is called from 'current directory' (no leading path - $0 is the file)
    $scriptfile =~ /(.*\\)(.*)$/
      && do { $scriptdir = $1; $scriptfile = $2; }    # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}
use lib "$scriptdir..";

use praqma::acc;
use Getopt::Long;
use File::Basename;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $BUILD);

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(new);

use constant MAX_SEMAPHORE_FILE_AGE_DAYS => 0.168;             # real (1 hr ~ 0.042 --> 4 hrs ~ 0.168)
use constant SEMAPHORE_DIR               => '\\semaphores';    # Relative to the script location dir
use constant CONFIGFILES                 => '/trcfg/';         # Custom configuration files here

# File version
$VERSION = "1.1";
$BUILD   = "8";

our $header = <<ENDHEADER;
#########################################################################
#     This module contains subs that come in handy in when
#     you write triggers in ClearCase
#     Date:       2009-06-26
#     Author:     Lars Kruse, lak\@praqma.net
#     Copyright:  Praqma A/S
#     License:    GNU GPL v3.0
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE         EDITOR        NOTE
-----------  ------------- ----------------------------------------------------
2009-06-26   Lars Kruse    First release of the module prepared for
                           Novo Nordisk A/s. It is based on the old
                           trigger_utils module (version 1.0.1)
2009-08-11   Lars Kruse    Changed path to the semaphore file to use
                           back-slashes (version 1.0.2)
2009-08-25   Lars Kruse    Changed the return value of enable_semaphore()
                           to be the status of the semaphore look-up.
                           (version 1.0.3)
2009-11-06  Lars Kruse     Changed the interface and semantics of
                           enable_install. (version 1.1.4)
2009-11-26  Jens Brejner   Add support for spaces in script path
2010-06-04  Jens Brejner   Removed check for vob-owner in sub enable_install
                           (version 1.1.6)
2010-07-06  Jens Brejner   rmtype in replicated vob requires switch -rmall
                           (version 1.1.7)

-------------------------------------------------------------------------------
ENDREVISION

sub new {
    my $class = shift;    #Cache the package name
    my $self  = {};
    bless( $self, $class );
    return $self;
}

sub require_trigger_context() {

    defined( $ENV{CLEARCASE_VOB_PN} ) || die "$main::header\nFile version: $main::VERSION.$main::REVISION\n$main::revision";
}

sub enable_semaphore_backdoor($) {
    my $msg = "";    #The status level of the semphore file.

    # If the semaphor file exists and it's not older than MAX_SEMAPHORE_FILE_AGE_DAYS
    # then the trigger will exit silently with 0 - allowing the event the trigger subscribed to, to carry on

    my $semaphore_dir  = $scriptdir . SEMAPHORE_DIR;
    my $semaphore_file = $semaphore_dir . "\\" . lc( $ENV{'username'} );

    my ( $mainpath, $mainscript ) = acc::split_dir_file($main::0);
    if ( -e $semaphore_file ) {
        $msg = "Script '$mainscript' found semaphore file at '$semaphore_file'\n";
        if ( ( -M $semaphore_file ) > MAX_SEMAPHORE_FILE_AGE_DAYS ) {
            $msg = $msg . "...but it's too old to stop us!";
        }
        else {
            open( SEMAPHORE, $semaphore_file ) || print $msg = $msg . "...Failed to open the semaphore file for read\n" && return;
            my @sempahore = grep( /^\s*$mainscript\s*$/i, <SEMAPHORE> );
            close(SEMAPHORE);

            if ( scalar @sempahore ) {
                $msg = $msg . "...and found the script '$mainscript' listed in the semphore file\nThe trigger script is canceled by semaphore!\n";
                print $msg;
                exit 0;
            }
            $msg = $msg . "...but it doesn't mention '$mainscript' so the trigger is allowed to continue\n";
        }
    }
    else {
        $msg = "Script '$mainscript' looked for semaphore file at '$semaphore_file'\n...but there wasn't any\n";
    }
    return $msg;
}

sub enable_install($$) {
    my ( $sw_install, $sw_vob, $sw_script, $sw_trigger, $sw_preview );
    my %options = (
        "install"   => \$sw_install,
        "vob=s"     => \$sw_vob,
        "script=s"  => \$sw_script,
        "trigger=s" => \$sw_trigger,
        "preview"   => \$sw_preview,
    );
    GetOptions(%options);

    return 0 unless defined($sw_install);

    my $usage = <<ENDUSAGE;
  $::Scriptfile -install -vob vob_tag [-script script_pname]
              [-trigger trigger_name] [-preview]

  -install                Required to run the script in install mode
  -vob vob_tag            The VOB where the trigger should be installed
  -script script_pname    The loation of the trigger script defaults to
                          the script´s own current path name ($0 as seen
                          from the perl script). Since triggers must be executed
                          from a loaction that is globally supported  - on Windows
                          it´s UNC path in the format \\\\server\\share\\... - the
                          path name to the trigger script be given in UNC format-
                          The switch is only used to override the default value
                          N.B: Show caution if you use this switch, you could
                          probably just go with the script´s default location
                          unless you´re testing or debugging!
  -trigger trigger_name   The name of the trigger. The trigger has a default name,
                          as stated by the designer inside the script, this is only
                          used if you wish to override the triggers default name.
  -preview                Displays the cleartool command that installs the trigger,
                          but does not actually execute it. This switch allows you to
                          run the script even if you are not the VOB owner
ENDUSAGE

    my $self           = shift;
    my $installopt_ref = shift;
    my %installopt     = %$installopt_ref;

    my $key_name     = 'name';
    my $key_support  = 'supports';
    my $key_mktrtype = 'mktrtype';
    my ( $trigger_name, $trigger_support, $trigger_mktrtype );

    $trigger_name     = $installopt{$key_name};
    $trigger_support  = $installopt{$key_support};
    $trigger_mktrtype = $installopt{$key_mktrtype};

    die "The trigger name should have been passed in a key named '$key_name' but it wasn't\n"
      unless ( defined($trigger_name) );

    die "The trigger support option should have been passed in a key named '$key_support' but it wasn't\n"
      unless ( defined($trigger_support) );

    die "The trigger mktrtype option should have been passed in a key named '$key_mktrtype' but it wasn't\n"
      unless ( defined($trigger_mktrtype) );

    #Assert -vob switch is applied
    die "ERROR -vob is required in -install mode.\n\n$usage\n"
      unless defined($sw_vob);

    #Assert VOB is available (test by querying the VOB owner)
    my $vobowner = lc(`cleartool desc -fmt \%[owner]p vob:$sw_vob`);
    die "ERROR $sw_vob is not accessible\n\n$usage\n"
      unless ( not $? );

    #Assert path to the trigger script is fully qualified
    my $trigger_pname = ( defined $sw_script ) ? $sw_script : $::Scriptdir . $::Scriptfile;
    die "Only fully qualified paths are allowed: '$trigger_pname' is not valid.\n\n$usage\n"
      unless ( $trigger_pname =~ /^\\\\/ ) || ( $trigger_pname =~ /^[a-zA-Z]:\\/ );

    #Assert the path to the trigger script is valid
    die "The script '$trigger_pname' is not accessible\n\n$usage\n"
      unless ( -e $trigger_pname );

    my @vobtypes = acc::get_vobtypes($sw_vob);
    my @allowed_vob_context = split( ',', $trigger_support );
    push @allowed_vob_context, lc($trigger_name);

    # match the two arrays against each other - get out as soon as a match is found
    my $match;
    foreach my $vt (@vobtypes) {
        $match && last;
        foreach my $avc (@allowed_vob_context) {
            ( lc($vt) eq lc($avc) ) && do { $match = $vt; last }
        }
    }

    $match || do {
        my $vtlist;
        foreach (@vobtypes) { $vtlist = $vtlist . $_ . ","; }
        chop($vtlist);
        print "[-]\t$trigger_name' does not qualify for VOB '$sw_vob' ($vtlist)\n";
        uninstall_trtype( $trigger_name, $sw_vob );
        exit 0;
    };

    # Check if there is a blacklist disqualifying the installation
    # Get the ACC_TriggerBlacklist attribute: a csv list of blacklisted trigger names

    my $cmd               = "cleartool desc -s -aattr " . acc::ATTYPE_TRIGGER_BLACKLIST . " vob:$sw_vob";
    my $raw_triggerblattr = `$cmd`;
    $? && die "Execution of: [$cmd] failed\n";    # assert success
    chomp($raw_triggerblattr);
    $raw_triggerblattr =~ s/\"//g;                # get rid of the 'required' quotes in CC string attributes
    my @blacklist = split( ',', $raw_triggerblattr );    # make a list;

    my $bl_match = 0;
    foreach my $bl (@blacklist) {
        $bl_match = ( lc($bl) eq lc($trigger_name) );
        $bl_match && last;
    }

    $bl_match && do {
        print "[-]\t$trigger_name' match the role as [$match] but the trigger is blacklisted on VOB '$sw_vob'.\n";
        uninstall_trtype( $trigger_name, $sw_vob );
        exit 0;
    };

    print "[+]\t$trigger_name' match the role as [$match] on VOB '$sw_vob'.\n";

    # Check if the trigger is already set (in which case we must use the -replace switch)
    my $trigger_tag = defined($sw_trigger) ? $sw_trigger : $trigger_name;

    my $replace = ( has_trtype( $trigger_tag, $sw_vob ) ) ? "-replace " : "";

    # enclose path in double qoutes and escapes there are spaces in the path
    if ( $trigger_pname =~ / / ) {
        $trigger_pname = "\\\"$trigger_pname\\\"";
    }

    #Compile the trigger installation command
    my $trig_inst_com = "\"Created using the -install switch of $::Scriptfile\"";
    my $current_trigger_install =
        "cleartool"
      . " mktrtype $replace"
      . $trigger_mktrtype
      . " -c $trig_inst_com -exec \""
      . acc::TRIGGER_PERL
      . " $trigger_pname\" $trigger_tag\@$sw_vob 2>&1";

    #If all the uses wanted was a preview it's time to get out
    defined($sw_preview) && do {
        print "Trigger install command:\n$current_trigger_install\n";
        exit 0;
    };

    #Else you do your thing
    exit system("$current_trigger_install");
}

sub has_trtype($$) {
    my $trtype = shift;
    my $vob    = shift;

    # Check if the trigger is already set (in which case we must use the -replace switch)
    my $cmd     = "cleartool desc trtype:$trtype\@$vob 2>&1";
    my $cmdexec = `$cmd`;

    #scalar_dump(\$cmd);
    $? && return 0;
    return 1;
}

sub uninstall_trtype($$) {
    my $trtype = shift;
    my $vob    = shift;
    has_trtype( $trtype, $vob ) && do {

        # If doing rmtype in replicated vob switch -rmall is required
        my $cmd               = "cleartool des -fmt %[vob_replication]p vob:$vob";
        my $replicationstatus = qx($cmd);
        if ( $replicationstatus =~ m/^replicated/i ) {
            $replicationstatus = " -rmall";
        }
        else {
            $replicationstatus = "";
        }

        $cmd = "cleartool rmtype $replicationstatus trtype:$trtype\@$vob 2>&1";
        my $cmdexec = `$cmd`;
        $? && do {
            print STDERR "ERROR: Failed to remove trigger:\n" . "[Command:]\n$cmd\n" . "[Returned:]\n$cmdexec\n";
            die;
        };

        print "The trigger '$trtype' was uninstalled from the VOB $vob\n";
    };

}

sub scalar_dump($) {
    my $ref = shift;
    my ( $package, $filename, $line ) = caller;
    print STDERR "   ########   Dumping scalar   ########\n"
      . "   Package:          \t$package '$filename'\n"
      . "   Line:             \t$line\n"
      . "   $ref: \t["
      . $$ref . "]\n";
}

## The CLEARCASE_MTYPE variable tells which type is involved
## ...in clear text (%@\#$¤) we need it as a type prefix
sub mtype2cctype($$) {
    my $mtyperef = shift;
    my $ccvarref = shift;
    my %types    = (
        'branch type'    => 'brtype',
        'label type'     => 'lbtype',
        'attribute type' => 'attype',
        'element type'   => 'eltype',
        'trigger type'   => 'trtype',
        'hyperlink type' => 'hltype'
    );
    return 0 unless defined( $types{$$mtyperef} );    # Return as FALSE if the match was unsuccesful
    $$ccvarref = $types{$$mtyperef};
    return 1;
}

sub get_config {

    my ( $self, $parms ) = @_;

    # Get the pathnames
    my $cfgname    = "config.$::Scriptfile";
    my $defaultcfg = "$::Scriptdir/$cfgname";
    my $customcfg  = $::Scriptdir . CONFIGFILES . $cfgname;

    # my $configfile = -e $customcfg ? $customcfg : $defaultcfg ;
    if ( -e $defaultcfg ) {

        # read defaults, all option defaults
        do $defaultcfg;
        no strict 'vars';
        while ( ( my $k, $v ) = each(%trigger_parms) ) {
            $$parms{$k} = $v;
        }

        #         my %def = %trigger_parms;
        if ( -e $customcfg ) {

            # if custom options, update those that are different

            do $customcfg;
            while ( ( my $k, $v ) = each(%trigger_parms) ) {
                $$parms{$k} = $v;
            }

        }
    }
    else {
        die "Expected to find a config file at $defaultcfg\n ";
    }
}

sub DESTROY {
}

1;

__END__

=pod

=head1 NAME

ACC - trigger helper module

=head1 DESCRIPTION

package: C<trigger_helper>

Module:  C<trigger_helper.pm>

The C<trigger_helper> package contains various functions that will come in handy when you write ClearCase triggers.

=head1 SYNOPSIS

B<Disable Triggers Using Semaphore Files>

C<trigger_helper> enables you to make triggers that doesn't execute if semaphores file has been created. This is useful if you have batch job
or some scheduled maintenance jobs that runs regularly and you want to allow them to run without triggering the triggers. The semaphores
could also prove helpful if you have a bad trigger, that's misbehaving in the environement, then the semaphore will enable you to I<disable> it temporarily
until you have time to fix without actually I<unisnstalling> it.

The semaphore files are located in a dedicated directory underneath the trigger directory. Normally users only have read access to this directory.
So security and policy enforcement handled by triggers is still intact - users still can't disable triggers as the whish, they'll need approval
form the admins.

B<Trigger Installation and Trigger Deployment>

C<trigger_helper> also has a feature that enables you to easily install triggers. We have devided VOBs into four types af genericly meaningful chunks: PVOBs, AdminVOBs, UCM component vobs and Base ClearCase client VOBs. Alle VOB will
match one (and only one) of the types. When you define trigges simply state what type(s) og VOS it should be installed on - and if you want to define your
own type (e.g. "MyKindOfSpecialDocumentVob") then that is supported too.

All you have to do in your trigger scripts is to define a hash of key+value pairs which you pass to the trigger_helper. The trigger_helper will
know what to do with it and all you triggers will support an install  syntax like the following:

  mytrigger.pl -install -vob \SomeVob

The trigger vill only install on the VOB if it's actually of the type that your trigger is designed for. You can simply execute install on I<all> your triggers
on I<all> your VOBs - and they will only be installed where they are designed to be installed.

Imagin the ease of trigger maintenance this provides e.g. across MultiSites and for creating new VOBs.

B<Self-explaining Trigger Scripts>

The trigger_helper also makes your trigger scripts behave naturally from a I<regular> perl-script point-of.-view. Trigger_helper identifies if the perl-script is
executeed outside a trigger-context and if it is - it will just show you a nice syntax/usage message insted af doing nothing or something unexpected.

=head1 FUNCTIONALITY

=head2 Putting I<trigger_helper> to work

=for html The trigger_helper is designed to be executed in a structure like the one in the <a target="_blank" href="http://launchpad.net/acc">Accelerated ClearCase Open Source Project</a>:

=for man  The trigger_helper is designed to be executed in a structure like the one in the \fIAccelerated ClearCase Open Source Project\fR ("http://launchpad.net/acc"):

 acc
   triggers
   praqma
   utils

To put the trigger_helper in use, you'll need to add an C<use lib> I<<the parent directory>> statement to your current script and then include the C<praqma::trigger_helper>.
Therefore you'll need to determine the location of your running script. It can all be done in a pre-compiled block using a setup like this:

 our ($Scriptdir, $Scriptfile);BEGIN{$Scriptdir =".\\";$Scriptfile = $0; $Scriptfile =~/(.*\\)(.*)$/ &&  do{$Scriptdir=$1;$Scriptfile=$2;}}
 use lib "$Scriptdir..";
 use praqma::trigger_helper;

Then to utilize the functionallity from the trigger helper you can throw in the following stetements:

 our $thelp=trigger_helper->new;          # Instantiates the trigger helper
 $thelp->enable_install(%install_params); # See more under "enable_install"
 $thelp->require_trigger_context;         # Simple check, that exits if the script is not called as a trigger
 $thelp->enable_semaphore_backdoor;       # See more under "enable_semaphore_backdoor"

Plese note that C<trigger_helper> requires access to C<acc.pm> in the I<ACC perl utility library>, as it uses subs and constants from it!

=head2 Making Triggers Support the I<-install> Switch

When you call C<enable_install(%install_params)> on your newly created trigger_helper object script, as shown above, then
you actually make your trigger scripts support the following syntax (when executed outside a trigger context):

 YourScriptName.pl -install -vob vob_tag [-script script_pname]
                   [-trigger trigger_name] [-preview]

 -install                Required to run the script in install mode
 -vob vob_tag            The VOB where the trigger should be installed
 -script script_pname    The loation of the trigger script defaults to
                         the script´s own current path name ($0 as seen
                         from the perl script). Since triggers must be executed
                         from a loaction that is globally supported  - on Windows
                         it´s UNC path in the format \\server\share\... - the
                         path name to the trigger script be given in UNC format-
                         The switch is only used to override the default value
                         N.B: Show caution if you use this switch, you could
                         probably just go with the script´s default location
                         unless you´re testing or debugging!
 -trigger trigger_name   The name of the trigger. The trigger has a default name,
                         as stated by the designer inside the script, this is only
                         used if you wish to override the triggers default name.
 -preview                Displays the cleartool command that installs the trigger,
                         but does not actually execute it. This switch allows you to
                         run the script even if you are not the VOB owner

=head2 Make the Triggers Support Silent Exit When Semaphore Files Exist

The trigger helper can make your triggers support a concept of semaphore files, which will allow the triggers to
exit silently under certain conditions. The concept is simply that when then semaphore backdoor is enabled in your scripts
it will check to see if a valid semaphore file exist - and if does - then the script exits silently with exit code 0.

The effect is always that the script is disabled - nothing happens.

The use of semaphore files should obviously be used with caution, since the triggers are designed to run, disabeling them means that
you get at different behaviour than desired. But on the other hand it's quite comman that some triggers actually du a bit of work, checking conditions,
validating states, enforcing policies etc.

Imagine that you have a nightly scheduled job that is doing some kind of maintenance work, and that work is causing some of the triggers to run - event though
you know for sure, that the maintenance script is compliant with you policies. In that case you can simply bypass the script - without actually uninstalling it.
It will continue to run for all users - except for the user running the maintenance script.

Another scenario where we use the semaphore files is in cases where triggers turn out to be buggy, and these bugs are discoverd by end-users in the
environment. Imagine that the fault in the trigger script is of such a nature that the most common regular use is supported allright, but a few users has
enterered a more complex scenario which - for some reason - wasn´t tested and not these users are stuck due to the misbehaving triggers. Obviously you must
fix it, but you afe prevented from doing it right I<now>. If you trigger enabels the semaphore backdoore you can now disable the script only for the few
users who are affected by the micbehaviour - while the rest of the users still execute it.

Lets have a look at how it works.

What you do is that you call the C<enable_semaphore_backdoor> class method on the trigger_helper object you just created.

The method will locate directory where the valid semaphores are supposed to be. This location is defined by a constant named C<SEMAPHORE_DIR> and the value must
be a search path that is relative to lovcation of the current script (the trigger script). The default value that we use in our script is C</semaphores>. Thus a recap
of the ACC file structure now lokks like this:

 acc
   triggers
     semaphores
   praqma
   utils

OK, so the C<enable_semaphore_backdoor> method will look for files which are named with the userid of the current user in this location.

If the file exist the method will validate that it's not too old. The definition of what I<too old> means is defined by another constant named
C<MAX_SEMAPHORE_FILE_AGE_DAYS>. We use 0.168 as our default value, taht equals to appromimately 4 hours. So if the semaphore file exists and it's not
too old the the method reads it to see if the name of the current scripts is listed in there - and if it is then then it exists silently.

You can lean more details about the semaphore backdoor in the section about the C<enable_semaphore_backdoor> class.

=head1 RESTRICTIONS

When the script runs autside a trigger context, it's designed to install triggers, and therefore it has the same restrictions as applies to trigger installation in general. That is; it can
only run if it is executed by the VOB owner or member of ClearCase Administrators group. Execptions are if the script is run with the C<-preview> switch, in which case
any ClearCase user can run it. Another exception is if you are replacing an existing trigger, then the current owner of the trigger is also allowed to execute.

I the current version, the installation procedure only support C<mktrtype> - that is triggers attached to VOBs. If you which to use it for
creating triggers on other objects - which implies using the C<mktrigger> command - then you need to do some hacking yourself.

There is still more details revealed about the installation of triggers in the section comming up regarding the C<enabel_install> class method.

=head1 CLASS METHODS

=head2 C<enable_install (%install_params)>

To apply the enable_install functionality, your trigger script needs to be called outside a trigger context with the -install switch (as described earlier).

Inside your script you will have to create a hash of key+value pairs and pass it to the C<enable_install> method. The hash must - in the current version - contain

The following three keys:

=over

=item *
name

=item *
mktrtype

=item *
supports

=back

B<name>

Is the name of the trigger to be installed. If the trigger already exists it will be replaced.

B<mktrtype>

Is the part of the cleartool C<mktrtype> sub-command that you would normally want to execute,
but stripped for the following switches:

  [-c comment | -cfile pname | -cq | -cqe | -nc]
  {-exec command-invocation |
     -execunix command-invocation |
     -execwin command-invocation |
     -mklabel label-type-selector |
     -mkattr attr-type-selector=value |
     -mkhlink hlink-type-selector,{to|from}=pname} ...
  [-replace]
  type-selector ...

These switches are all derived automatically from the context of the execution.

B<supports>

The value os this key is a list (array) of VOB types that supports this trigger.

We have defined four generic VOB types which together covers I<all> VOBs in the world - that is, any VOB will map
to exactly one of the types. These generic types are:

  pvob               = A UCM Project VOB
  adminvob           = The definition is a VOB pointed to by one or more AdminVOB hyperlinks and which is not an UCM Project VOB
  ucmvob             = A Vob containing UCM components, defined as a VOB pointing to a UCM Project VOB with an AdminVOB hyperlink
  bccvob             = All VOBs that doesn't fall into one of the above categories

If your world of VOB types is more sophisticated than the four generic types above then you can simpy define your own VOB types by
attaching the VOB type name you have invented to the VOB object by use of the C<attype:ACC_VOBType> - like this:

  cleartool mkattr ACC_VOBType "\"documentvob\"" vob:\MyDocVob

Once you have done that, you are free to refer to the self-invented VOB type 'documentvob' in your I<supports> list.

The I<supports> list implicitly includes the trigger name itself, that meant, if a VOB has included a trigger name in the c<ACC_VOBType> attribute
then that particular trigger will install. like this:

  cleartool mkattr ACC_VOBType "\"ACC_RMEMPTYBR,ACC_CHOW_ON_MKELEM\"" vob:\MyVob

Will enable then installation of two triggers triggers on \MyVob.


If a trigger is supporting more than one type of VOBs (e.g remove empty branch trigger) then you simply add all types to the list. Just make a not that the trigger
installs if it maps to I<any> of the listed types. So if you have invented your own VOB types as described above, you might want to consider
using those as your only references in the trigger install prodecures.

I<B<Note>>:

The generic VOB type names listed above are and the then name of the attribute type that defineds custom VOB types are defined by constants
in the C<acc.pm> module like this:

  use constant VOBTYPE_PVOB                => 'pvob';
  use constant VOBTYPE_ADMINVOB            => 'adminvob';
  use constant VOBTYPE_UCM_CLIENT          => 'ucmvob';
  use constant VOBTYPE_BCC_CLIENT          => 'bccvob';
  use constant ATTYPE_CUSTOM_VOBTYPE       => 'ACC_VOBType';

An example of how the hash that is passed to C<enable_install> is constructed could be:

 my %install_params = (
    'name'        => 'TRIGGER_NAME',                          # string - no whitespaces
    'mktrtype'    => '-element -all postop mkelem',           # string - with whitespaces
    'supports'    => ('bccvob','ucmvob');                        # Array of generic and/or custom VOB types

=head2 C<enable_semaphore_backdoor>


To support the semaphore backdoor your trigger script needs to call the C<enable_semaphore_backdoor> method as described earlier.

In order for a semaphore file to be valid - and effectively disable the trigger the following  properties must me met:

=over

=item *

A semaphore file named after the user must exist

=item *

The semaphore file must be located in a subfolder of the actual trigger loctaion named  C<semaphores>

=item *

The semaphore file must have been created (not accessed, or updated, but CREATED) within the last 4 hours

=item *

The semaphore file must contain a line stating the name of the perl script it is supposed to detronize (eg. no_rmelem_rmver.pl), the
same semaphore file can list many scritps.

=back

If a valid semaphore exist the trigger execution is canceled.

I<B<Note>>:

The location of the C<semaphores> directory can be tweak by setting the constant C<trigger_helper::SEMAPHORE_DIR>.

This time span defining how long time a sempahore file is valid can be tweaked by setting the constant C<trigger_helper::MAX_SEMAPHORE_FILE_AGE_DAYS>.

=head1 EXAMPLES

You could investigate some of the triggers in the Accelerated ClearCase Open Source Project to see some real-life examples


=for comnment the section above should probably be deleted

=head1 AUTHOR

"Lars Kruse" E<lt>lak@praqma.netE<gt>.

=head1 SUPPORT AND BUGS REPORT

For current status of the Accelerated ClearCase Project regarding bug status, features on their way, features you would like to see, asking questions in general
and for reporting bugs you've found please visit the ACC project's home at http://launchpad.net/acc .

=head1 COPYRIGHT and LICENSE

This program is distributed under GNU GPL v3.0, http://www.gnu.org/licenses/gpl-3.0.html

=cut
