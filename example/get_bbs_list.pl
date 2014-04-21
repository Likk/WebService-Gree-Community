use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::RealBin/../lib";

use Config::Pit;
use YAML;
use WebService::Gree::Community;

my $id = shift @ARGV or die "required community id";

my $ws = do { #prepare
    $ENV{EDITOR} ||= 'vim';
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

{ # scrape bbs_list
    my $bbs_list = $ws->get_bbs_list( community_id => $id) || [];
    print Encode::decode_utf8(YAML::Dump $bbs_list);
}

