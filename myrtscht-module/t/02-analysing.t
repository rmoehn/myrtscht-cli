use strict;
use warnings;

use Test::Command tests => 8;
use Test::More;
use Cwd;

my $myrtscht =
    cwd() . '/script_files/myrtscht';
chdir '/tmp' or die "Couldn't change into /tmp: $!";

ok((grep /ttourn/, glob '*'),
    'The script before the former script seems to have worked properly.');
chdir 'ttourn' or die "Couldn't change into ttourn/: $!\n";

is(scalar(grep /\d{2}.d/, glob '*'), 2,
    'The former script seems to have worked properly.');

# testing the analysing by using the whole directory
my $analyse_gamefs_dir = Test::Command->new(
    cmd => "$myrtscht -a 01.d -d"
);

$analyse_gamefs_dir->exit_is_num(0);
$analyse_gamefs_dir->stderr_isnt_eq('');
$analyse_gamefs_dir->stdout_is_eq('');

# testing the analysing by using the particular files
chdir '02.d' or die "Couldn't change into ttourn/: $!\n";
my $analyse_gamefs_file = Test::Command->new(
    cmd => "$myrtscht -a *.s"
);

$analyse_gamefs_file->exit_is_num(0);
$analyse_gamefs_file->stderr_is_eq('');
$analyse_gamefs_file->stdout_is_eq('');
