use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use WebService::Gree::Community;
use Config::Pit;
use utf8;
my ($ws);
my $community_id = shift @ARGV;
my $thread_id    = shift @ARGV;
die "required community id and thread id" if not defined $community_id or not defined $thread_id;

{ #prepare
  my $pit = pit_get('gree.jp', require => {
      mail_address  => 'your mail_address on gree.jp',
      password      => 'your password on gree.jp',
    }
  );

  $ws = WebService::Gree::Community->new(
    %$pit
  );
}
{ # scrape member open_social_id
  my $bbs = $ws->show_bbs(
    community_id => $community_id,
    thread_id    => $thread_id,
  ) || [];
  use YAML;
  print YAML::Dump [ sort @$bbs ];
}

