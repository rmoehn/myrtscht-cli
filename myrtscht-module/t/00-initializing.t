use strict;
use warnings;

use Test::Command tests => 5;
use Test::More;

my $myrtscht =
    '/home/moses/Perl/Myrtscht/myrtscht-module/script_files/myrtscht';
chdir '/tmp' or die "Couldn't change into /tmp: $!";

# testing the initializing of a tournament
my $init_tourn = Test::Command->new(
    cmd => [$myrtscht, qw(-n ttourn -g 2 -d 2)]
);

$init_tourn->exit_is_num(0);
$init_tourn->stdout_is_eq('');
$init_tourn->stderr_isnt_eq('');

ok((grep /ttourn/, glob '*'), 'Tournament directory created.');
chdir 'ttourn' or die "Couldn't change into ttourn/: $!\n";

is(scalar(grep /\d{2}\.g/, glob '*'), 2, 'All group files aboard.'); 
