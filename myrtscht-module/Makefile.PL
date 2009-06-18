use 5.008000;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'myrtscht',
    VERSION_FROM      => 'script_files/myrtscht', 
    PREREQ_PM         => {
        Log::Log4perl                 => 1,
        Games::Tournament::RoundRobin => 0,
        Net::CUPS                     => 0},
    ($] >= 5.005 ?
      (ABSTRACT_FROM  => 'script_files/myrtscht',
       AUTHOR         => 'Richard Möhn <myrtscht@cpan.org>') : ()),
);
