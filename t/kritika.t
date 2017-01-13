use strict;
use warnings;

use Test::More;
use Test::MonkeyMock;
use Cwd qw(getcwd);
use JSON ();
use Devel::Cover::DB;

use_ok 'Devel::Cover::Report::Kritika';

subtest 'report: submits correct report' => sub {
    my $ua     = _mock_ua();
    my $report = _build_report();

    no warnings 'redefine';
    no strict 'refs';
    local *{"$report\::_build_ua"} = sub { $ua };

    local $ENV{KRITIKA_TOKEN}         = 'deadbeef';
    local $ENV{TRAVIS_COMMIT}         = 'abcdef';
    local $ENV{CI_BUILD_REF}          = 'abcdef';
    local $ENV{DEVEL_COVER_DB_FORMAT} = 'Sereal';

    my $cwd = getcwd();
    chdir 't/data/devel_cover';
    my $db = Devel::Cover::DB->new(db => 'cover_db');

    $report->report($db);

    chdir $cwd;

    my ($url, $form, $options) = $ua->mocked_call_args('post_form');
    is_deeply $options, {headers => {Authorization => 'Token deadbeef'}};

    is $form->{revision}, 'abcdef';
    is_deeply JSON::decode_json($form->{coverage})->[0]->{summary},
      {
        'statement' => {
            'total'   => 21,
            'covered' => 18
        },
        'branch' => {
            'total'   => 6,
            'covered' => 3
        },
        'function' => {
            'total'   => 6,
            'covered' => 5
        },
        'condition' => {
            'covered' => 2,
            'total'   => 3
        }
      };
};

done_testing;

sub _mock_ua {
    my $ua = Test::MonkeyMock->new;
    $ua->mock(post_form => sub { {success => 1} });
    return $ua;
}

sub _build_report { 'Devel::Cover::Report::Kritika' }
