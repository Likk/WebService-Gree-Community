use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use WebService::Gree::Community;
use Config::Pit;
use utf8;
my ($ws);
my $id = shift @ARGV;
die "required community id" unless $id;
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
  my $members = $ws->get_members( id => $id) || [];
  use YAML;
  print YAML::Dump [ sort @$members ];
}

