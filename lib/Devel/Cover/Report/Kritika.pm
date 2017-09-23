package Devel::Cover::Report::Kritika;
use strict;
use warnings;

our $VERSION = '0.05';

use List::Util qw(sum);
use HTTP::Tiny;
use JSON ();
use Devel::Cover::DB;

sub report {
    my $class = shift;
    my ( $db, $options ) = @_;

    my $config = $class->_detect_config;

    my $coverage = $class->_parse_db($db);

    $class->_post( $config, $coverage );

    print "Coverage submitted to `$config->{base_url}`\n";
}

sub _detect_config {
    my $class = shift;

    my $ini = {};

    if ( -f '.kritikarc' ) {
        my @content = do { open my $fh, '<', '.kritikarc'; <$fh> };
        foreach my $line (@content) {
            next unless length $line;
            next if $line =~ m/^#/;

            chomp( my ( $key, $value ) = split /\s*=\s*/, $line, 2 );

            $ini->{$key} = $value;
        }
    }

    my $token = $ENV{KRITIKA_TOKEN} || $ini->{token}
      or die "KRITIKA_TOKEN is not defined\n";
    my $base_url =
         $ENV{KRITIKA_BASE_URL}
      || $ENV{KRITIKA_HOST}
      || $ini->{base_url}
      || 'https://kritika.io';

    return {
        token    => $token,
        base_url => $base_url
    };
}

sub _post {
    my $class = shift;
    my ( $config, $coverage ) = @_;

    $coverage = JSON::encode_json($coverage);

    my $ua = $class->_build_ua;

    my $response;
    for my $i ( 1 .. 3 ) {
        $response = $ua->post_form(
            "$config->{base_url}/upload/coverage",
            {
                revision => $class->_detect_revision,
                coverage => $coverage
            },
            { headers => { Authorization => 'Token ' . $config->{token} } }
        );

        last if $response->{success};

        last unless $response->{status} eq '599';

        warn "Retrying in ${i}s because of $response->{reason}: "
          . "$response->{content}...\n";
        $class->_sleep($i);
    }

    if ( !$response->{success} ) {
        my $error = $response->{reason};

        if ( $response->{status} eq '599' ) {
            $error .= ': ' . $response->{content};
        }

        die "Error: $error\n" unless $response->{success};
    }
}

sub _sleep { shift; sleep(@_) }

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
    foreach my $file ( sort @files ) {
        my $lines   = {};
        my $summary = {};

        my $f = $cover->file($file);

        for my $criterion ( $f->items ) {
            next if $criterion eq 'time' || $criterion eq 'pod';

            my $c = $f->criterion($criterion);

            for my $location ( $c->items ) {
                my @calls = @{ $c->location($location) };

                if ( $criterion eq 'subroutine' || $criterion eq 'statement' ) {
                    my $realcriterion = $criterion;
                    $realcriterion = 'function'
                      if $realcriterion eq 'subroutine';

                    $summary->{$realcriterion}->{total} += @calls;
                    $summary->{$realcriterion}->{covered} ||= 0;

                    $lines->{$location}->{$realcriterion}->{total} += @calls;
                    $lines->{$location}->{$realcriterion}->{covered} ||= 0;

                    if ( my @covered = grep { $_->covered } @calls ) {
                        $lines->{$location}->{$realcriterion}->{covered} +=
                          @calls;
                        $summary->{$realcriterion}->{covered} += @calls;
                    }
                }
                elsif ( $criterion eq 'branch' || $criterion eq 'condition' ) {
                    my $total = sum map { $_->total } @calls;
                    my $covered =
                      sum map { $_ ? 1 : 0 } map { $_->values } @calls;

                    $lines->{$location}->{$criterion}->{total}   += $total;
                    $lines->{$location}->{$criterion}->{covered} += $covered;

                    foreach my $call (@calls) {
                        push @{ $lines->{$location}->{$criterion}->{hits} },
                          [ map { $_ ? 1 : 0 } $call->values ];
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
                map { { line => $_, coverage => $lines->{$_} } }
                sort { $a <=> $b } keys %$lines
            ]
          };
    }

    return $coverage;
}

sub _build_ua {
    my $class = shift;

    return HTTP::Tiny->new( agent => "$class/$VERSION " );
}

1;
__END__

=head1 NAME

Devel::Cover::Report::Kritika - Cover reporting to Kritika

=head1 SYNOPSIS

    export KRITIKA_TOKEN=yourtoken
    cover -test -report kritika

=head1 DESCRIPTION

L<Devel::Cover::Report::Kritika> reports coverage to L<Kritika|https://kritika.io>.

In order to submit the report, you have to set C<KRITIKA_TOKEN> environmental variable or `token` option in C<.kritikarc>
to the appropriate token, which can be obtained from Kritika web interface.

When using on premise version of Kritika the webservice address can be specified by setting C<KRITIKA_BASE_URL>
environmental variable or `base_url` option in C<.kritikarc>.

=head1 INTEGRATION

L<Devel::Cover::Report::Kritika> was written having in mind the integration possibility with many public/private CI/CD
services.

It will detect the following services:

=over 4

=item * L<Travis CI|https://travis-ci.org/>

=item * L<GitLab|https://about.gitlab.com/gitlab-ci/>

=back

=head1 DEVELOPMENT

=head2 Repository

    http://github.com/kritikaio/devel-cover-report-kritika-perl

=head1 CREDITS

=head1 AUTHOR

Viacheslav Tykhanovskyi, C<vti@cpan.org>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2017, Viacheslav Tykhanovskyi

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=cut
