package praqbal;
require 5.001;
require Exporter;

use strict;

our( $Scriptdir, $Scriptfile );
BEGIN {
    $Scriptfile = $0;
    $Scriptfile =~ /(.*\\)(.*)$/ && do { $Scriptdir = $1; $Scriptfile = $2; }
}

use Getopt::Long;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
				split_dir_file
				scalar_dump
				);


=head1 NAME

PraqmaLib Globals module

=head1 SYNOPSIS

package: C<praqbal>

Module:  C<praqbal.pm>

This module contains shared definitions for PraqmaLib modules and commonly used functions


=head1 DESCRIPTION


=head1 CONSTANTS

The module defines the following constants which you might consider to give different values:

C<MAX_SEMAPHORE_FILE_AGE_DAYS>        = C<0.168>

Tha value  of C<MAX_SEMAPHORE_FILE_AGE_DAYS> determins how long time a semaphore file is valid. The value is given
as number of days (1 hr ~ 0.042 --> 4 hrs ~ 0.168).

C<SEMAPHORE_DIR>                      = C<'./semaphores'>

The value of C<SEMAPHORE_DIR> is the relative to the script location directory where the semaphore file will be
searched for.

=cut

use constant TRIGGER_PERL => 'ratlperl';                         # -c "perl interpreter for triggers scripts"

###############################################################

sub split_dir_file($){

=head2 split_dir_file( $path )

Splits a path in two: the directory part and the file name part

Parameters:

 $path = The path to split.

Returns:

 ($dir, $file) A two-item array.

=cut


  my ($dir, $file);
  $file = shift;
  $dir =".\\";
  $file =~/(.*\\)(.*)$/ &&  do{
    $dir=$1;
    $file=$2;
  };
  return ($dir, $file);
}

sub scalar_dump($) {

=head2 scalar_dump($)

Dumps scalar to STDERR

=cut

    my $ref = shift;
    my ( $package, $filename, $line ) = caller;
    print STDERR "   ########   Dumping scalar   ########\n"
      . "   Package:          \t$package '$filename'\n"
      . "   Line:             \t$line\n"
      . "   $ref: \t["
      . $$ref . "]\n";
}

