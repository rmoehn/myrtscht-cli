use strict;
use warnings;

use Test::Command tests => 7;
use Test::More;
use Cwd;

my $myrtscht =
    cwd() . '/script_files/myrtscht';
chdir '/tmp' or die "Couldn't change into /tmp: $!";

ok((grep /ttourn/, glob '*'),
    'The former script seems to have worked properly.');
chdir 'ttourn' or die "Couldn't change into ttourn/: $!\n";

# testing the processing of the group files
my $proc_groupfs = Test::Command->new(
    cmd => "$myrtscht -p *.g -s"
);

# write the data into the group files
open GROUPFILE, '>', '01.g'
    or die "Couldn't open 01.g for reading: $!\n";
print GROUPFILE << "EOF";
Name: Group1
Tables: 1
Members:
mem1 g1
mem2 g1
mem3 g1
mem4 g1
EOF

open GROUPFILE, '>', '02.g'
    or die "Couldn't open 02.g for reading: $!\n";
print GROUPFILE << "EOF";
Name: Group2
Tables: 2, 3, 4
Members:
mem1 g2
mem2 g2
mem3 g2
mem4 g2
mem5 g2
EOF

close GROUPFILE;

$proc_groupfs->exit_is_num(0);
$proc_groupfs->stderr_is_eq('');
$proc_groupfs->stdout_is_eq('');

my @filedirs;
is(scalar(grep /\d{2}\.d/, glob '*'), 2,
    'All tournament directories aboard.'); 
is(scalar(@{$filedirs[0]} = sort glob '01.d/*.s'), 6,
    'All game files in the first directory.'); 
is(scalar(@{$filedirs[1]} = sort glob '02.d/*.s'), 10,
    'All game files in the second directory.'); 

# We have to write some results into the game files.
{
my @results = (     # Somehow nice-looking, isn't it?
    [[3,  11],
     [7,  11]],

    [[12, 10],
     [1,  11],
     [3,  11]],

    [[7,  11],
     [11, 9],
     [12, 10]],

    [[2,  11],
     [1,  11]],

    [[11, 4],
     [11, 7]],

    [[6,  11],
     [3,  11]],

    [[1,  11],
     [11, 9],
     [2,  11]],

    [[12, 10],
     [14, 12]],

    [[11, 13],
     [5,  11],
     [13, 11]],
    [[11, 8],
     [11, 8]]
);

for my $dir (@filedirs) {
     @results = reverse @results;  # In the first directory are the
                                   # same results but in reverse order.

     for (my $i = 0; $i < @$dir; $i++) {
         open GAMEFILE, '>>', $dir->[$i];
         for my $fileres (@{$results[$i]}) {
             print GAMEFILE join("\t", @$fileres), "\n";
         }
     }
}

close GAMEFILE;
}
