use strict;

my ( $project_unmatched, $branch_unmatched );

my $helpmsg = <<ENDHELP;

Usage: $0 -run [vobtag]

-run      $0 must receive "-run" as first parameter to execute 
          -so it doesn't execute unless you want it to.
[vobtag]  The second parameter can be a valid vobtag, so 
          only that vob will be processed, but if it is not 
          defined, $0 will default to process all project vob's (ucmvob).        

ENDHELP

die "$helpmsg" unless $ARGV[0] =~ /.run/i;
my @pvobs = defined( $ARGV[1] ) ? $ARGV[1] : get_pvobs();

foreach my $vobtag (@pvobs) {
  print "Investigating projects in vob $vobtag\n\n";
  $project_unmatched = 0;
  $branch_unmatched  = 0;
  my @projects  = &get_projects($vobtag);
  my $vobexists = qx("cleartool des -s vob:$vobtag");
  if ($?) {
    die "$vobexists\n $helpmsg";
  }
  foreach my $proj (@projects) {
    &set_streamlock($proj);
  }
  print "\nFixed $project_unmatched Project-Stream mismatches and $branch_unmatched Stream-Branch mismatches in $vobtag\n";
}

################## S U B S #############################

sub set_branchlock ($) {

  # read stream lock, ensure that the  branch type follows the project lock
  my $stream = shift;
  my @slock  = get_lock_info($stream);
  my $brtype = get_guardbranch($stream);

  # We are done if there is not brtype
  return unless ($brtype);

  my @brtype_lockstatus = get_lock_info($brtype);

  if ( $slock[1] ne $brtype_lockstatus[1] ) {
    $branch_unmatched++;
    print "\nMICMATCH $stream [" . $slock[0] . "] --> $brtype [" . $brtype_lockstatus[0] . "]\n";

    #case stream isn't locked
    ( $slock[0] eq "unlocked" ) && do {

      print "Stream $stream is not locked, unlocking branch $brtype\n";
      system("cleartool unlock $brtype");
      return;
    };

    #case stream is locked, some users can be excluded from lock;
    ( $slock[0] eq "locked" ) && do {
      print "Stream $stream is locked, locking branch $brtype\n";

      # Lock might not be for all

      # Cache nuser list if exists
      my $nuserlist = "";
      if ( $slock[1] =~ /(.*except.*:\s+)(.*)/ ) {
        print "[$1]\n";
        print "[$2]\n";

        $nuserlist = " -nuser " . join( ',', split( / /, $2 ) );
      }

      # Cache comment if exists
      my $lockcomment = $slock[2] ? "-c \"$slock[2]\"" : "";

      # Must unlock a locked object before modifying it
      system("cleartool unlock $stream");
      ( $brtype_lockstatus[0] ne "unlocked" ) && do {
        system("cleartool unlock $brtype");
      };
      system("cleartool lock $lockcomment $nuserlist $brtype");
      system("cleartool lock $lockcomment $nuserlist $stream");
      return;
    };

    #case stream is locked obsolete;
    ( $slock[0] eq "obsolete" ) && do {
      system("cleartool unlock $stream");
      ( $brtype_lockstatus[0] eq "locked" ) && do {
        system("cleartool unlock $brtype");
      };
      system("cleartool lock -obsolete $brtype");
      system("cleartool lock -obsolete $stream");
      return;
    };

  }

}

sub get_guardbranch ($) {

  # Read stream hyperlink pointing to the branch type
  # Returns the fqn branch type if found, else 0 (zero)
  my $stream    = shift;
  my $retval    = 0;
  my $direction = "->";
  my $hltype    = "IndependentGuard";                             # UCM Keyword
  my $ln        = qx("cleartool desc -ahlink $hltype $stream");

  if ( $ln =~ /\s*$hltype\s*$direction\s*(.*)\s*$/ ) {
    $retval = $1;
    chomp($retval);

  }
  return $retval

}

sub set_streamlock ($) {

  # read project lock, ensure that the stream follows the project lock
  my $project    = shift;
  my @plock      = get_lock_info($project);
  my @streamlist = qx("cleartool lsstream -obsolete -fmt %Xn\\n -in $project");
  chomp @streamlist;
  print "Checking " . scalar(@streamlist) . " stream(s) in $project: ";

  foreach my $stream (@streamlist) {

    my $nuser = 0;
    my @slock = get_lock_info($stream);
    print ".";
    if ( $plock[1] ne $slock[1] ) {
      $project_unmatched++;
      if ( $slock[1] =~ /(.*except.*:\s+)(.*)/ ) {
        $nuser = 1;
      }
      print "\nMICMATCH $project [" . $plock[0] . "] --> $stream [" . $slock[0] . "]\n";

      #case project isn't locked
      ( $plock[0] eq "unlocked" ) && do {

        print "Project is not locked";
        if ($nuser) {
          print ", but stream is locked with -nuser switch\n";
        }
        else {
          print "\n";
          system("cleartool unlock $stream");
        }
      };

      #case project is locked, some users can be excluded from lock;
      ( $plock[0] eq "locked" ) && do {
        print "Stream is locked ";

        # Lock might not be for all
        if ( $plock[1] =~ /(.*except.*:\s+)(.*)/ ) {

          # project with stream which is is locked with -nuser, we don't touch the stream
        }

        # unlock unless already locked -nuser
        unless ($nuser) {
          system("cleartool unlock $stream") unless ( $slock[0] eq "unlocked" );
          system("cleartool lock $stream");
        }
      };

      #case stream is locked obsolete;
      ( $plock[0] eq "obsolete" ) && do {
        system("cleartool unlock $stream") if ( $slock[0] ne "unlocked" );
        system("cleartool lock -obsolete $stream") unless ($nuser);

      };

    }
    set_branchlock($stream);
  }

  print "\n";

}

sub get_projects ($) {

  # find all projects, return an array of the fqn projects
  my $vob    = shift;
  my @retval = qx("cleartool lsproj -obsolete -fmt %Xn\\n -invob $vob");
  chomp @retval;
  return @retval;

}

sub get_pvobs {

  # find all pvobs, return an array of the vobtags
  my @retval = grep { /(ucmvob)/ } qx("cleartool lsvob ");
  foreach (@retval) {
    s/(^..)(\S+)(\s+.*$)/$2/;
    chomp;
  }
  return @retval;
}

sub get_lock_info ($) {

  # read info an object's lock (if any)
  # return as array

  my $object = shift;

  # capture lock status
  my @retval = qx("cleartool desc -fmt %[locked]p $object");

  # add additional info about the lock
  push @retval, qx("cleartool lslock -fmt %Nc $object");
  foreach (@retval) { chomp; }
  return @retval;

}

=pod

=head1 SYNOPSIS

In ClearCase UCM make the underlying branch type follow the lock type of the Project


=head1 DESCRIPTION

In ClearCase UCM all streams belongs to a project, and each stream can have an associated branch type.
Locking a project obsolete, is hiding it from the GUI, but the lock is not automatically cascaded down to the streams, nor their branch types.

This script makes a project's streams and branch types follow the lock state of the project

=head2 Lock types

An object can be locked in 4 variants:

unlocked; not locked.

locked; visible, and locked of all users.

locked -nuser; visible and locked for most users, but not for the users in the nuser list

locked -obsolete; invisible and locked of all users.

This script will make all streams under a project, and their corresponding branch types match the project's lock.

=head2 -nuser lock - the exception from the rule

The -nuser locks are handled as follows:

A -nuser project lock will be handled as a normal lock (for all users) and cascade to the stream, which will the result in a lock on the branch type.

A -nuser stream lock will cascade to the associated branch type.

But it will not be changed by lock, lock -nuser or none (unlocked) on the project, whereas a lock -obsolete on the project will override
the -nuser stream lock and cascade to the stream and it's branch.


=cut
