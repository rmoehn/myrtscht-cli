use strict;
use warnings;

use Test::Command tests => 15;
use Test::More;
use Cwd;

my $myrtscht = 'script_files/myrtscht';

# testing the --help call
my $help_help = Test::Command->new(
    cmd => "$myrtscht --help"
);

$help_help->exit_is_num(1);
$help_help->stdout_isnt_eq('');
$help_help->stderr_is_eq('');

# testing the -h call
my $help_h = Test::Command->new(
    cmd => "$myrtscht -h"
);

$help_h->exit_is_num(1);
$help_h->stdout_isnt_eq('');
$help_h->stderr_is_eq('');

# testing the --version call
my $help_version = Test::Command->new(
    cmd => "$myrtscht --version"
);

$help_version->exit_is_num(0);
$help_version->stdout_isnt_eq('');
$help_version->stderr_is_eq('');

# testing the call without arguments
my $no_args = Test::Command->new(
    cmd => "$myrtscht"
);

$no_args->exit_is_num(2);
$no_args->stdout_is_eq('');
$no_args->stderr_like(qr/Usage:.*/x);

# testing the call with wrong arguments
my $wrong_args = Test::Command->new(
    cmd => "$myrtscht"
);

$wrong_args->exit_is_num(2);
$wrong_args->stdout_is_eq('');
$wrong_args->stderr_like(qr/Usage:.*/x);
