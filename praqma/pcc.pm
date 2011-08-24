package praqma::pcc;

# must live in Some/Module.pm
use strict;
require Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

# set the version for version checking $VERSION = 0.01;
@ISA         = qw(Exporter);
@EXPORT      = qw(&func1 &func2 &func4);
%EXPORT_TAGS = ();

# eg: TAG => [ qw!name1 name2! ],
# your exported package globals go here,
# as well as any optionally exported functions
@EXPORT_OK = qw($Var1 %Hashit &func3);
use vars qw($Var1 %Hashit);

# non-exported package globals go here
use vars qw(@more $stuff);

# initialize package globals, first exported ones
$Var1   = '';
%Hashit = ();

# then the others (which are still accessible as $Some::Module::stuff)
$stuff = '';
@more  = ();  

# all file-scoped lexicals must be created before
# the functions below that use them.
# file-private lexicals go here
  
my $priv_var    = '';
my %secret_hash = ();

# here's a file-private function as a closure,
# callable as &$priv_func.
my $priv_func = sub {

  # stuff goes here.
};

# make all your functions, whether exported or not;
#######################################################################################
sub DESTROY {
   my $self = shift;
   printf("$self dying at %s\n", scalar localtime);
  
}

# no prototype
sub func1 {

  return if (1);
}

# proto'd void
sub func2() { 

  return if (1); 
}

# proto'd to 2 scalars
sub func3($$) {

  return if (1);
}
     
# this one isn't auto-exported, but could be called!
# proto'd to 1 hash
sub func4(\%) {
  return if (1);
}
 
# ref END { return if (1); }

# module clean-up code here (global destructor)
1;
