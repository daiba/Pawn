#!/usr/bin/env perl
package App::Pawn::script;
use Term::ReadLine;
use Getopt::Long;
use strict;

sub new {
    my $class = shift;
    bless {
        argv => [],
        @_,
    }, $class;
}

sub parse_options {
    my $self = shift;
    local @ARGV = @{ $self->{argv} };
    push @ARGV, @_;

    Getopt::Long::Configure("bundling");
    Getopt::Long::GetOptions(
        'f|file=s' => \$self->{file},
        't|test'   => \$self->{test},
        's|shell'  => \$self->{shell},
        'h|help'   => sub { $self->help },
    );
    $self->{argv} = \@ARGV;
}

sub help {
    my $self = shift;
    die <<HELP;
Usage: pawn [options] File

Optons:
  -h,--help       this message
  -f,--file       specify rules directory
  -s,--shell      simple shell
  -t,--test       test mode (send no mail)
HELP
}

sub load_file {
    my $self = shift;
    return unless $self->{file} && -e $self->{file};
    my $file   = $self->{file};
    my @attr   = qw( name hosts command eachTime endTime );
    my $plugin = { file => $file };

    my $dsl = join "\n",
      map "sub $_ {my \$e=shift || return \$plugin->{$_}; \$plugin->{$_}=\$e }",
      @attr;
    my $code = do { open my $io, "<$file"; local $/; <$io> };

    eval "package App::Pawn::Rule;\n" . "use strict;\nuse utf8;\n$dsl\n$code";
    die $@ if ($@);
}

sub loop {
    my $self = shift;
    my @hosts = split /\s+/, App::Pawn::Rule::hosts();
    my %ret;

    if ( $self->{shell} ) {
        my $term = Term::ReadLine->new('Rook');
        my $out = $term->OUT || \*STDOUT;
        while ( defined( my $line = $term->readline('Rook> ') ) ) {
            next if $line =~ /^\s*$/;
            for my $host (@hosts) {
                next unless ($host);
                my $fd;
                open $fd, '-|', "ssh $host $line 2> /dev/null";
                my $output;
                {
                    local $/ = undef;
                    $output = <$fd>;
                }
                close $fd;
                print $out $output;
            }
        }
    }
    else {
        for my $host (@hosts) {
            next unless ($host);
            my $fd;
            my $command = App::Pawn::Rule::command();
            open $fd, '-|', "ssh $host $command 2> /dev/null";
            my $output;
            {
                local $/ = undef;
                $output = <$fd>;
            }
            $ret{$host} = App::Pawn::Rule::eachTime()->($output);
            close $fd;
        }
    }
    App::Pawn::Rule::endTime()->( \%ret );
}

sub doit {
    my $self = shift;
    $self->load_file;
    $self->loop;
}

package main;

unless (caller) {
    my $app = App::Pawn::script->new;
    $app->parse_options(@ARGV);
    $app->doit;
}