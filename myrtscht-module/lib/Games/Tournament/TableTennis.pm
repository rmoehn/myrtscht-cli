package Games::Tournament::TableTennis;

use 5.008000;
use strict;
use warnings;
use Log::Log4perl qw( :easy );
use Cwd;
use Games::Tournament::RoundRobin;
use Net::CUPS;
use Net::CUPS::Destination;

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
        create_new_tournament
        process_group_files
        preprocess_game_files
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
        create_new_tournament
        process_group_files
        preprocess_game_files
);

our $VERSION = '0.02';


# the subroutine for creating a new tournament
sub create_new_tournament {
    my $options               = shift;

    # creating the directory in which the tournament is stored
    {
    my @date           = (localtime)[4,3,5];
    my $tournam_dir = 
        $options->{n} || sprintf(
                "Tournament-%02d%02d%d",
                $date[0] + 1,
                $date[1],
                $date[2] + 1900);
    mkdir($tournam_dir, 0755)
        or die "Couldn't make tournament directory $tournam_dir: $!\n";
    DEBUG "Generated new tournament directory: $tournam_dir.";
    chdir $tournam_dir
        or die "Couldn't change into tournament directory "
             . "$tournam_dir: $!\n";
    DEBUG "Now in tournament directory $tournam_dir.";
    }
   
    # write the group template into all the group files
    my $groupnr = $options->{g} || 10;
    my @groupfiles;
    for (my $i = 1; $i <= $groupnr; $i++) {
        my $groupfname = sprintf("%02d.g", $i);
        open(GROUPFILE, ">", $groupfname)
            or die "Couldn't open group file $groupfname for "
                 . "writing: $!\n";
        print GROUPFILE <<"EOF";
Name:
Tables:
Members:

EOF
    
        DEBUG "Wrote template to group file: $groupfname";
    }
    INFO "Created the group files.";
}

# the subroutine for processing group files, making game files and
# making/printing game sheets
sub process_group_files {
    my $options    = shift;
    my $groupfiles = shift;
    my $cwd        = getcwd;
    my $printfile  = "gamesheets";
    my $printer;

    # We have to compute some things therewith the printout looks
    # nice later.
    # The number of lines per sheet of A4 paper must be 67 and 67
    # must be the number of lines per sheet of A4 paper as thou have
    # to use A4 paper with a number of 13 chars per column to get 
    # nice results.
    my $maxsetnr        = ($options->{r} || 2) * 2 - 1;
    my $gamesheetheigth = $maxsetnr + 6;
    my $gamesheets      = sprintf("%d", 67 / $gamesheetheigth);
    my $newlines        = 67 - $gamesheets * $gamesheetheigth;
    DEBUG "The game sheets are $gamesheetheigth high. Hence we can "
        . "put $gamesheets of the on one column and have to insert "
        . "$newlines newlines after them in order to make CUPS happy.";

    # the format for the printout; Alas, I can't declare the
    # variables in a smaller scope. (Or don't know it better.)
    my($groupname, $id, $table, $roundcnt, $member1, $member2);
    my $printoutform = 
          "format GAMEPRINT =                                      \n"
        . 'Group: @' . '<' x 36                                 . "\n"
        . '$groupname'                                          . "\n"
        . 'Round: @<<<< Table: @<<<<' . ' ' x 10 . 'ID: @<<<<'  . "\n"
        . '$roundcnt, $table, $id'                              . "\n"
        . '-'  x 22 . '+' . '-' x 21                            . "\n"
        . '@' . '|' x 20 . ' |' . '@' . '|' x 20                . "\n"
        . '$member1, $member2'                                  . "\n"
        . '-'  x 22 . '+' . '-' x 21                            . "\n"
        . (' ' x 22 . '|' . ' ' x 21 . "\n") x $maxsetnr
        . '-'  x 22 . '+' . '-' x 21                            . "\n"
        . ".\n"; # I love formats. Especially if they are dynamic.
    DEBUG $printoutform if defined $options->{d};
    eval $printoutform;
    die $@ if $@;
        
    # initialize the printing things
    # invoke the spooler or not
    unless (defined $options->{s}) {
        my $cups = Net::CUPS->new()
            or warn "Couldn't get a nice CUPS---we "
                  . "won't be able to print.\n";
        $printer = $cups->getDestination($options->{P})
            or warn "Couldn't get your printer's destination: "
                  . "You have to specify another.\n";
        $printer->addOption("cpi", 13);
        $printer->addOption("columns", 2);
    } 

    # process the group files one by one
    for my $groupfile (@$groupfiles) {
        my $groupfnr = substr($groupfile, 0, 2);

        # manage the group directory
        {
        my $groupdir = "$groupfnr.d";
        mkdir($groupdir, 0755)
            or die "Couldn't make group directory $groupdir: $!\n";
        rename($groupfile, "$groupdir/$groupfile")
            or die "Couldn't move group file $groupfile to "
                 . "group directory $groupdir: $!\n";
        chdir $groupdir
            or die "Couldn't change into group directory $groupdir: $!";
        DEBUG "Now in group directory $groupdir.";
        }

        # It's a silly place, but I didn't find a better.
        open(GAMEPRINT, ">>", $printfile)
            or die "Couldn't open printfile $printfile for "
                 . "appending: $!\n";
        select((select(GAMEPRINT), $|++)[0]);

        # read the groupfile
        open(GROUPFILE, "<", $groupfile)
            or die "Couldn't open group file $groupfile for "
                 . "reading: $!\n";
        chomp(my @gf_content = <GROUPFILE>);
        close GROUPFILE;
        DEBUG "Group file content: @gf_content";
        $groupname  = substr(shift @gf_content, 6);
        DEBUG "The group is named $groupname.";
        my @tables  = split(m([ ,;.:/]+), substr(shift @gf_content, 8));
        DEBUG "It plays at the tables @tables.";
        shift @gf_content;
        my @members = @gf_content;
        DEBUG "It consists of @members.";
        undef @gf_content;

        # create the schedule for the group
        my @schedule;
        {
        DEBUG "The schedule:";
        my $group = Games::Tournament::RoundRobin->new(
                league => \@members
                );
        for (my $i = 1; $i <= $group->rounds(); $i++) {
            my %round;
            my %raw_schedule = %{ $group->membersInRound($i) };
            my %parsed_values;
            DEBUG "Round $i.";
            for my $member (keys %raw_schedule) {
                next if $member eq "Bye";
                next if $raw_schedule{$member} eq "Bye";
                next if $parsed_values{$member};
                $round{$member} = $raw_schedule{$member};
                $parsed_values{$round{$member}} = 1;
            } # The data structure created by the module has doubled
              # pairings and silly members named Bye. So I have to build
              # a better one. I also could delete() the regarding, but
              # I like this way better.
            push(@schedule, \%round);
            DEBUG "The schedule now: @schedule";
        }
        }

        # process the schedule and create the necessary files
        {
        my($gamecnt, $appendcnt);

        for my $round (@schedule) {
            $roundcnt++;
            for my $member (keys %{ $round }) {
                $id      = $groupfnr . sprintf("%02d", ++$gamecnt);
                $table   = shift @tables;
                $member1 = $member;
                $member2 = $round->{$member};
                my $gamefile = sprintf("%02d.s", $gamecnt);
                push(@tables, $table);

                # create the gamefile
                open(GAMEFILE, ">", $gamefile)
                    or die "Couldn't open game file $gamefile for "
                         . "for writing: $!\n";
                print GAMEFILE "$member | $round->{$member}\n";

                # append to the print file
                write GAMEPRINT;
                $appendcnt++;
                if ($appendcnt == $gamesheets) {
                    print GAMEPRINT "\n" x $newlines;
                    $appendcnt = 0;
                }
            }
        }
        }

        # print out or do something else
        unless (defined $options->{s}) {
            $printer->printFile($printfile, $printfile)
                or die "Couldn't print out: $!\n";
            unlink $printfile
                or warn "Couldn't remove print file $printfile: $!\n";
        }

        chdir $cwd
            or die "Couldn't change into former directory $cwd: $!\n";
        DEBUG "Back in $cwd.";
    }
    INFO "Created the schedule.";
}

# the subroutine preprocessing the game files
# But it just preprocesses and gives the files directly to the
# true processing subroutine.
sub preprocess_game_files {
    my $options         = shift;
    my $file_containing = shift;

    # process the input and filter out just the game files to
    # give to the following routine
    if (-d $file_containing->[0]) {
        DEBUG "We have a directory with game files given.";
        my $dirname = $file_containing->[0];
        opendir(GROUPDIR, $file_containing->[0])
            or die "Couldn't open group directory "
                 . "$file_containing->[0]: $!\n";
        @$file_containing = readdir GROUPDIR;
        closedir GROUPDIR;
        chdir $dirname
            or die "Couldn't change into groupdirectory $dirname: $!\n";
    } else {
        DEBUG "We have a list of game files given.";
    }
    my @gamefiles = grep { /\.s$/ } @$file_containing;
    DEBUG "Giving game files @gamefiles to the game file processor.";
    &process_game_files($options, \@gamefiles);
}

# the subroutine preprocessing the game files
sub process_game_files {
    no warnings;
    my $options   = shift;
    my $gamefiles = shift;
    my (%players, $player, $rank);

    # process the game file and create the data structure
    for my $gamefile (@$gamefiles) {
        open(GAMEFILE, "<", $gamefile)
            or die "Couldn't open gamefile $gamefile for reading: $!\n";
        my($name1, $name2);
        my $numcont; # It controls whether we actually have the first
                     # line of a game file (with the names) or one of
                     # the other lines (with the results given).

        while (<GAMEFILE>) {
            chomp;
            next if /#/;
            if (/(.+) \| (.+)/) {
                ($name1, $name2) = ($1, $2);
                 DEBUG "The players are $name1 and $name2.";
                 $numcont = 0;
            } else {
                ($players{$name1}{balls}, $players{$name2}{balls})
                    = /(\d+)\D+(\d+)/;
                DEBUG "Result: $1 : $2";
                $numcont = 1;
            }

            $players{$name1}{all_fails} += $players{$name2}{balls},
            $players{$name2}{all_fails} += $players{$name1}{balls},
            $players{$name1}{all_balls} += $players{$name1}{balls},
            $players{$name2}{all_balls} += $players{$name2}{balls},
            $players{$name1}{ball_difference} +=
              ($players{$name1}{balls} - $players{$name2}{balls}),
            $players{$name2}{ball_difference} +=
              ($players{$name2}{balls} - $players{$name1}{balls}),
                if $numcont;

            if ($numcont and
                    $players{$name1}{balls} > $players{$name2}{balls}) {
                $players{$name1}{sets_won}++;
                $players{$name1}{all_sets_won}++;
                $players{$name2}{sets_lost}++;
                $players{$name2}{all_sets_lost}++;
            } elsif ($numcont) {
                $players{$name2}{sets_won}++;
                $players{$name2}{all_sets_won}++;
                $players{$name1}{sets_lost}++;
                $players{$name1}{all_sets_lost}++;
            }
            $players{$name1}{balls} = 0; # Just for this game
            $players{$name2}{balls} = 0; #
        }

            if ($players{$name1}{sets_won}
                    > $players{$name2}{sets_won}) {
                $players{$name1}{wins}++;
                $players{$name2}{losts}++;
            } else {
                $players{$name2}{wins}++;
                $players{$name1}{losts}++;
            }

            $players{$name1}{set_difference} +=
              ($players{$name1}{sets_won} - $players{$name2}{sets_won});
            $players{$name2}{set_difference} +=
              ($players{$name2}{sets_won} - $players{$name1}{sets_won});

            $players{$name1}{sets_won} = 0; # Just for this game.
            $players{$name2}{sets_won} = 0; #
    }
    # I know, this whole thing is very very ugly. But how ugly
    # would it be  if there were no hashes? On top of that it
    # produces occasional warnings. But I think, if it
    # wouldn't produce occasional warnings, it would also be
    # far more ugly.
    close GAMEFILE;
    INFO "Processed the game files.";

    # sort the people according to their games
    my @ranking = sort {
        $players{$b}{wins}           <=> $players{$a}{wins}           or
        $players{$b}{set_difference} <=> $players{$a}{set_difference} or
        $players{$b}{ball_difference} <=> $players{$a}{ball_difference}
    } keys %players;
    DEBUG "Sorted all the stuff.";
    
    # generate the ranking file
    open(RANKING, ">", "ranking")
        or die "Couldn't open ranking file \"ranking\" for "
             . "writing: $!\n";
    select((select(RANKING), $= = 67)[1]);

    foreach $player (@ranking) {
        ++$rank;
        write RANKING;
    }
    INFO "Generated the ranking file.";

format RANKING_TOP =
Rank | Name                  |  Games  |   Sets    |  SD  |    Balls    |  BD
-----+-----------------------+---------+-----------+------+-------------+------
.
format RANKING =
#ra  | pl                    | wi : lo | sw  : sl  |  sd  | ba   : fa   | bd
@>>.@||@<<<<<<<<<<<<<<<<<<<<@||@> : @<@||@>> : @<<@||@|||@||@>>> : @<<<@||@||||
{$rank, "|", $player, "|",
$players{$player}{wins}            || 0, 
$players{$player}{losts}           || 0, "|",
$players{$player}{all_sets_won}    || 0,
$players{$player}{all_sets_lost}   || 0, "|",
$players{$player}{set_difference}  || 0, "|",
$players{$player}{all_balls}       || 0,
$players{$player}{all_fails}       || 0, "|",
$players{$player}{ball_difference} || 0
}
.
}

1;

__END__

=encoding utf8

=head1 NAME

Games::Tournament::TableTennis - Perl extension for managing round robins

=head1 SYNOPSIS

  use Games::Tournament::TableTennis;
  # and do something useful with it

=head1 DESCRIPTION

This module has currently no real common use. It is currently just
used to bring the main functions out of B<myrtscht|myrtscht>, the
actually most important part of this distribution, and thus make it
lighter. Hence I haven't documented this module yet. But I will do
this in the next time and in the time after the next time I will be
working on more commonly useful functions of
L<Games::Tournament::TableTennis|Games::Tournament::TableTennis>.


=head1 NOTE

Since this module is not yet designed for common use I do not
recommend to used it yourself if you do not know exactly what you do.
Rather look on L<myrtscht|myrtscht> (also included in this
distribution) and visit
L<Games::Tournament::TableTennis|Games::Tournament::TableTennis from
time to time.


=head1 SEE ALSO

=over 4

=item L<myrtscht>

The frontend program to this module.

=item L<Games::Tournament::MyrtschtTutEn>

A tutorial to myrtscht.

=item L<www.myrtscht.de|http://www.myrtscht.de>

A website concerning this program. Not really mature yet.

=item L<git://git.tuxfamily.org/gitroot/myrtscht/programrel.git>

The git repository with the current state of development. Use it by
typing

    git clone git://git.tuxfamily.org/gitroot/myrtscht/programrel.git

But beware: It is NOT stable.

=item L<Games::Tournament::RoundRobin>

A module which was very useful creating this module.


=head1 AUTHOR

Richard Möhn, E<lt>myrtscht@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Richard Möhn

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
