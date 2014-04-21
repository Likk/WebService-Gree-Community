use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::RealBin/../lib";

use Config::Pit;
use WebService::Gree::Community;
use YAML;

my $community_id = shift @ARGV;
my $thread_id    = shift @ARGV;
die "required community id and thread id" if not defined $community_id or not defined $thread_id;

my $ws = do { #prepare
    my $pit = pit_get('gree.jp', require => {
        mail_address  => 'your mail_address on gree.jp',
        password      => 'your password on gree.jp',
    });

    my $ws = WebService::Gree::Community->new(
        %$pit
    );
    $ws->guess_year(1);
    $ws;
};

{ # scrape bbs
    my $bbs = $ws->show_bbs(
        community_id => $community_id,
        thread_id    => $thread_id,
    ) || [];
    print Encode::decode_utf8(YAML::Dump [ sort @$bbs ]);
}

