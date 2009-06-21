use warnings;
use strict;

use File::Find;
use File::Path;
use Data::Compare;
use Storable;
use Test::Simple tests => 2;

# see that the all the things in the tournament directory are the same
# as at my computer

# read in my hash of the directory
my $my_dirstruct = retrieve 't/ttourn.dmp';

# create a hash of your directory
chdir '/tmp' or die "Couldn't change into /tmp: $!";

ok((grep /ttourn/, glob '*'),
    'The former script seems to have worked properly.');

undef $/;
my %your_dirstruct;
find(\&something_nice_in, 'ttourn');

sub something_nice_in {
    return if -d;
    open FILE, '<', $_ or die "Couldn't open file $_ for reading: $!\n";
    $your_dirstruct{$File::Find::name} = <FILE>;
}  
close FILE;

# compare thy and my structure
ok(Compare($my_dirstruct, \%your_dirstruct),
        'Hey, you seem to have the same directory as me.');

# tidying up a bit
chdir '/tmp' or die "Couldn't change into /tmp: $!";
rmtree('ttourn');
