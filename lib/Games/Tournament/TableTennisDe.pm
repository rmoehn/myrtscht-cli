package Games::Tournament::TableTennisDe;
our @EXPORT = qw(
        create_new_tournament
        process_group_files
        preprocess_game_files
        );
use Exporter;
our @ISA = qw( Exporter );
our $VERSION = '0.1a';

use strict;
use warnings;
use Log::Log4perl qw( :easy );
use Cwd;
use Games::Tournament::RoundRobin;
use Net::CUPS;
use Net::CUPS::Destination;

# the subroutine for creating new tournaments
sub create_new_tournament {
    my $options               = shift;
    my $specified_groupfnames = shift;

    # creating the directory in which the tournament is stored
    {
    my @date           = (localtime)[4,3,5];
    my $tournam_dir = 
        $options->{n} || sprintf(
                "Turnier-%02d%02d%d",
                $date[0] + 1,
                $date[1],
                $date[2] + 1900);
    mkdir($tournam_dir, 0755)
        or die "Konnte Turnierverzeichnis $tournam_dir nicht "
             . "erstellen: $!\n";
    DEBUG "Neues Turnierverzeichnis $tournam_dir erstellt.";
    chdir $tournam_dir
        or die "Konnte nicht in Turnierverzeichnis $tournam_dir "
             . "wechseln: $!\n";
    DEBUG "In das Turnierverzeichnis $tournam_dir gewechselt.";
    }
   
    # write the group template into all the group files
    my $groupnr = $options->{g} || 10;
    my @groupfiles;
    for (my $i = 1; $i <= $groupnr; $i++) {
        my $groupfname = sprintf("%02d.g", $i);
        open(GROUPFILE, ">", $groupfname)
            or die "Konnte Gruppendatei $groupfname nicht öffnen: $!\n";
        print GROUPFILE <<"EOF";
Name:
Tische:
Mitglieder:

EOF
    
        DEBUG "Vorlage in Gruppendatei $groupfname geschrieben.";
    }
    INFO "Gruppendateien erstellt.";
}

# the subroutine for processing group files, making game files and
# making/printing game sheets
sub process_group_files {
    my $options    = shift;
    my $groupfiles = shift;
    my $cwd        = getcwd;
    my $printfile  = "Spielzettel";
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
    DEBUG "Die Spielzettel sind $gamesheetheigth Zeilen hoch. Also "
        . "können wir $gamesheets von ihnen in eine Spalte schreiben "
        . "und müssen $newlines Leerzeilen danach einfügen."; 

    # the format for the printout; Alas, I can't declare the
    # variables in a smaller scope. (Or don't know it better.)
    my($groupname, $id, $table, $roundcnt, $member1, $member2);
    my $printoutform = 
          "format GAMEPRINT =                                      \n"
        . 'Gruppe: @' . '<' x 35                                . "\n"
        . '$groupname'                                          . "\n"
        . 'Runde: @<<<< Tisch: @<<<<' . ' ' x 10 . 'ID: @<<<<'  . "\n"
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
            or warn "Konnte keinn CUPS bekommen - wir werden "
                  . "nicht drucken können.\n";
        $printer = $cups->getDestination($options->{P})
            or warn "Konnte das Ziel des Druckers nicht "
                  . "herausfinden. Bitte nimm einen anderen.\n";
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
            or die "Konnte Gruppenverzeichnis $groupdir nicht "
                 . "anlegen: $!\n";
        rename($groupfile, "$groupdir/$groupfile")
            or die "Konnte Gruppendatei $groupfile nicht nach "
                 . "Gruppenverzeichnis $groupdir verschieben: $!\n";
        chdir $groupdir
            or die "Konnte nicht in Gruppenverzeichnis $groupdir "
                 . "wechseln: $!";
        DEBUG "Nun in Gruppenverzeichnis $groupdir.";
        }

        # It's a silly place, but I didn't find a better.
        open(GAMEPRINT, ">>", $printfile)
            or die "Konnte Spielzetteldatei $printfile nicht zum "
                 . "Anhängen öffnen: $!\n";
        select((select(GAMEPRINT), $|++)[0]);

        # read the groupfile
        open(GROUPFILE, "<", $groupfile)
            or die "Konnte Gruppendatei $groupfile nicht "
                 . "zum Lesen öffnen: $!\n";
        chomp(my @gf_content = <GROUPFILE>);
        close GROUPFILE;
        DEBUG "Gruppendateiinhalt: @gf_content";
        $groupname  = substr(shift @gf_content, 6);
        DEBUG "Die Gruppe heißt $groupname.";
        my @tables  = split(m([ ,;.:/]+), substr(shift @gf_content, 8));
        DEBUG "Sie spielt an den Tischen @tables.";
        shift @gf_content;
        my @members = @gf_content;
        DEBUG "Sie besteht aus @members.";
        undef @gf_content;

        # create the schedule for the group
        my @schedule;
        {
        DEBUG "Der Spielplan:";
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
            DEBUG "Der Spielplan jetzt: @schedule";
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
                    or die "Konnte $gamefile nicht "
                         . "zum Schreiben öffnen: $!\n";
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
                or die "Konnte nicht drucken: $!\n";
            unlink $printfile
                or warn "Konnte Spielzetteldatei "
                      . "$printfile nicht löschen: $!\n";
        }

        chdir $cwd
            or die "Konnte nicht in das vorherige "
                 . "Verzeichnis $cwd wechseln: $!\n";
        DEBUG "Wieder in $cwd.";
    }
    INFO "Spielplan erstellt.";
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
        DEBUG "Ah, ein Verzeichnis mit Spieldateien.";
        my $dirname = $file_containing->[0];
        opendir(GROUPDIR, $file_containing->[0])
            or die "Konnte das Gruppenverzeichnis "
                 . "$file_containing->[0] nicht öffnen: $!\n";
        @$file_containing = readdir GROUPDIR;
        closedir GROUPDIR;
        chdir $dirname
            or die "Konnte nicht in Gruppenverzeichnis "
                 . "$dirname wechseln: $!\n";
    } else {
        DEBUG "Ah, eine Liste mit Dateinamen.";
    }
    my @gamefiles = grep { /\.s$/ } @$file_containing;
    DEBUG "Gebe Spieldateien @gamefiles dem Spieldateiverarbeiter.";
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
            or die "Konnte Spieldatei $gamefile nicht öffnen: $!\n";
        my($name1, $name2);
        my $numcont; # It controls whether we actually have the first
                     # line of a game file (with the names) or one of
                     # the other lines (with the results given).

        while (<GAMEFILE>) {
            chomp;
            next if /#/;
            if (/(.+) \| (.+)/) {
                ($name1, $name2) = ($1, $2);
                 DEBUG "Die Spieler sind $name1 und $name2.";
                 $numcont = 0;
            } else {
                ($players{$name1}{balls}, $players{$name2}{balls})
                    = /(\d+)\D+(\d+)/;
                DEBUG "Ergebnis: $1 : $2";
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
    INFO "Spieldateien verarbeitet.";

    # sort the people according to their games
    my @ranking = sort {
        $players{$b}{wins}           <=> $players{$a}{wins}           or
        $players{$b}{set_difference} <=> $players{$a}{set_difference} or
        $players{$b}{ball_difference} <=> $players{$a}{ball_difference}
    } keys %players;
    DEBUG "Alles sortiert.";
    
    # generate the ranking file
    open(RANKING, ">", "Platzierungen")
        or die "Konnte Platzierungsdatei \"Platzierungen\" nicht "
             . "zum Schreiben öffnen: $!\n";
    select((select(RANKING), $= = 67)[1]);

    foreach $player (@ranking) {
        ++$rank;
        write RANKING;
    }
    INFO "Platzierungsdatei erstellt.";

format RANKING_TOP =
Rang | Name                  | Spiele  |   Sätze   |  SD  |    Bälle    |  BD
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

# Documentation will follow later.
