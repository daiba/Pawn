#!/usr/bin/env perl
package App::Pawn::script;
use Getopt::Long;
use Term::ReadLine;
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
        's|shell' => \$self->{shell},
        'h|help'  => sub { $self->help; exit },
    );
    $self->{argv} = \@ARGV;
}

sub help {
    my $self = shift;
    print <<HELP;
Usage: pawn.pl [options] File

Optons:
  -h,--help       this message
  -s,--shell      simple shell
HELP
}

sub load_file {
    my $self   = shift;
    my $file   = shift @{ $self->{argv} };
    my @attr   = qw( hosts commands copy );
    my $config = { file => $file };

    my $dsl = join "\n",
      map "sub $_ {my \$e=shift || return \$config->{$_}; \$config->{$_}=\$e }",
      @attr;
    $dsl .= <<DSL;

sub include {
    my \$b = shift || return;
    my \$f = dirname(\$file) . '/' . \$b;
    unless ( do \$f ) { die "can't include \$f\\n" }
}
DSL

    my $code = do { open my $io, "<", $file; local $/; <$io> };
    eval "package App::Pawn::Rule;\n"
      . "use File::Basename;\nuse strict;\nuse utf8;\n$dsl\n$code";
    die $@ if ($@);
}

sub loop {
    my $self = shift;
    if ( $self->{shell} ) {
        $self->shell;
    }
    else {
        $self->exec;
    }
}

sub shell {
    my $self  = shift;
    my @hosts = split /\s+/, App::Pawn::Rule::hosts();
    my $term  = Term::ReadLine->new('Pawn');
    my $out   = $term->OUT || \*STDOUT;
    while ( defined( my $line = $term->readline('Pawn> ') ) ) {
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
            chomp($output);
            close $fd;
            printf $out "%s> %s\n", $host, $output;
        }
    }
}

sub exec {
    my $self = shift;
    my @hosts = split /\s+/, App::Pawn::Rule::hosts();
    my %ret;
    for my $host (@hosts) {
        next unless ($host);
        my @doChecks = App::Pawn::Rule::commands()->();
        for my $doCheck (@doChecks) {
            my $do    = $$doCheck[0];
            my $check = $$doCheck[1];
            if ( ref($do) eq "CODE" ) {
                $self->scp( $host, $do, $check );
            }
            else {
                $self->ssh( $host, $do, $check );
            }
        }
    }
}

sub ssh {
    my $self = shift;
    my ( $host, $do, $check ) = @_;
    my $fd;
    open $fd, '-|', "ssh $host $do 2> /dev/null";
    my $output;
    {
        local $/ = undef;
        $output = <$fd>;
    }
    $check->($output);
    close $fd;
}

sub scp {
    my $self = shift;
    my ( $host, $do, $check ) = @_;
    my ( $com, $opt ) = $do->();
    $opt =~ s/HOST/$host/;
    my @com = split /\s+/, $opt;
    unshift @com, $com;
    $check->( system(@com) );
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
