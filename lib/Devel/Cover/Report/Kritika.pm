package Devel::Cover::Report::Kritika;
use strict;
use warnings;

our $VERSION = '0.01';

use List::Util qw(sum);
use HTTP::Tiny;
use JSON ();
use Devel::Cover::DB;

our $API_ENDPOINT =
  ($ENV{KRITIKA_HOST} || 'https://kritika.io') . '/upload/coverage';

sub report {
    my ($class, $db, $options) = @_;

    my $token = $ENV{KRITIKA_TOKEN};
    die 'KRITIKA_TOKEN is not defined' unless $token;

    my $coverage = $class->_parse_db($db);

    $class->_post($token, $coverage);

    print "Coverage submitted to `$API_ENDPOINT`\n";
}

sub _post {
    my $class = shift;
    my ($token, $coverage) = @_;

    $coverage = JSON::encode_json($coverage);

    my $ua       = $class->_build_ua;
    my $response = $ua->post_form(
        $API_ENDPOINT,
        {
            revision => $class->_detect_revision,
            coverage => $coverage
        },
        {headers => {Authorization => 'Token ' . $token}}
    );

    die $response->{reason} unless $response->{success};
}

sub _detect_revision {
    my $class = shift;

    for (
        qw/
        TRAVIS_COMMIT
        CI_BUILD_REF
        /
      )
    {
        return $ENV{$_} if $ENV{$_};
    }

    die 'Cannot detect revision';
}

sub _parse_db {
    my $class = shift;
    my ($db) = @_;

    my $coverage = [];

    my $cover = $db->cover;

    my @files = $cover->items;
    foreach my $file (sort @files) {
        my $lines   = {};
        my $summary = {};

        my $f = $cover->file($file);

        for my $criterion ($f->items) {
            next if $criterion eq 'time' || $criterion eq 'pod';

            my $c = $f->criterion($criterion);

            for my $location ($c->items) {
                my @calls = @{$c->location($location)};

                if ($criterion eq 'subroutine' || $criterion eq 'statement') {
                    my $realcriterion = $criterion;
                    $realcriterion = 'function'
                      if $realcriterion eq 'subroutine';

                    $summary->{$realcriterion}->{total} += @calls;
                    $summary->{$realcriterion}->{covered} //= 0;

                    $lines->{$location}->{$realcriterion}->{total} += @calls;
                    $lines->{$location}->{$realcriterion}->{covered} //= 0;

                    if (my @covered = grep { $_->covered } @calls) {
                        $lines->{$location}->{$realcriterion}->{covered} +=
                          @calls;
                        $summary->{$realcriterion}->{covered} += @calls;
                    }
                }
                elsif ($criterion eq 'branch' || $criterion eq 'condition') {
                    my $total = sum map { $_->total } @calls;
                    my $covered =
                      sum map { $_ ? 1 : 0 } map { $_->values } @calls;

                    $lines->{$location}->{$criterion}->{total}   += $total;
                    $lines->{$location}->{$criterion}->{covered} += $covered;

                    foreach my $call (@calls) {
                        push @{$lines->{$location}->{$criterion}->{hits}},
                          [map { $_ ? 1 : 0 } $call->values];
                    }

                    $summary->{$criterion}->{total}   += $total;
                    $summary->{$criterion}->{covered} += $covered;
                }
            }
        }

        my $realfile = $file;
        $realfile =~ s{^blib/}{};

        push @$coverage,
          {
            file    => $realfile,
            summary => $summary,
            lines   => [
                map { {line => $_, coverage => $lines->{$_}} }
                sort { $a <=> $b } keys %$lines
            ]
          };
    }

    return $coverage;
}

sub _build_ua {
    my $class = shift;

    return HTTP::Tiny->new(agent => "$class/$VERSION ");
}

1;
__END__