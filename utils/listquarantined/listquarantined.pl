
use File::Copy;

# Find directory to saving properties file
my $viewfile = ( split( /\s+/, qx(cleartool lsstgloc -view -region GRUNDFOS) ) )[2];

# These guys like partly dotted servernames, we can\t use that
$viewfile =~ s/([^\.]*)([^\\]*)(\\.*)/$1$3/;

# Defined view_q script path
my $view_q = $ENV{CCUTILS} . '\utils\view_q\view_q.pl';

#  Get views in quarantine
@list = grep { /:/ } qx(ratlperl $view_q -lsquarantine);
chomp @list;
foreach (@list) {
	# Jenkins plugin Extended Choice Parameter, uses backslash as escape, so we need to double them.
	s/\\/\\\\/g;
}

# Update outfile
my $old = $viewfile . '\view_q_stats.properties';
my $new = $old . '.temp';

open( NEW, "> $new" ) or die "can't open $new: $!";
if ( -e $old ) {
	open( OLD, "< $old" ) or die "can't open $old: $!";

	while (<OLD>) {

		# change $_, then...
		next if (/^quarantined/);
		print NEW $_ or die "can't write $new: $!";
	}
	close(OLD);
}

print NEW "quarantined=" . join( ',', sort(@list) ) . "\n" or die "can't write $new: $!";
close(NEW);

my $original = "$old.orig";
if ( -e $old ) {

	# print "Trying to copy [$old] to [$original]\n";
	copy( $old, $original ) or die "can't rename $old to $original: $!";
}

# print "Trying to rename [$new] to [$old]\n";
move( $new, $old ) or die "can't rename $new to $old: $!";
if ( -e $original ) {

	# print "Trying to delete [$original\n";
	unlink $original or die "can't unlink $original: $!";
}
print "File $old updated\n";

