# Configuration file for stop_twin.pl

our %trigger_parms = (
# Casesensensitive Name search
# 0 means off, so a CamelCase rename operation would be stopped
# 1 means on, so a CamelCase rename operation would not be seen as an evil twin attempt
"CaseSensitive" => 0,
# 0 means off, no automatic merge, based on based on best guess
# 1 means active. Partial merge of directory on best guess, do not check in
# 2 means active. Full automatic.Merge directory on best guess, check in changes.
"AutoMerge" => 1
);

__END__
