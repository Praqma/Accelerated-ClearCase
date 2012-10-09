my $path = 'users.ini';
open( INI, "< $path" ) or die "Couldn't open $path for reading: $!\n";

FILE: while (<INI>) {
    next FILE if (/\s*#/);
    next FILE if (/^\s+$/);
    chomp;
    if (/^\s*\[(.*)\].*/) {
        $section = $1;
    }

    if (/=/) {

        ( $keyword, $value ) = split( /=/, $_, 2 );

        # put them into hash
        ${ $hash{$section} }{$keyword} = $value;
    }
}

close(INI);

foreach my $section ( sort keys %hash ) {
    my %vals = %{ $hash{$section} };
    print "[$section]\n";
    foreach my $set ( sort keys %vals ) {
        print "\t $set = $vals{$set}\n";
    }

}

__END__

__DATA__

# comment

[sectionA]
key = value
speed = something
jen brejner = stuart
[section B]

dif = +++
uar = lskdf
