package WebService::Gree::Community;

=head1 NAME

WebService::Gree::Community - Gree community members info.

=head1 SYNOPSIS

  use WebService::Gree::Community;
  my $gree = WebService::Gree::Community->new(
    mail_address  => 'your mail_address',
    password      => 'your password',
    community_id  => 000000,
  );
  my $members = $gree->get_members;
  use YAML;
  print YAML::Dump $members;

=head1 DESCRIPTION

WebService::Gree::Community is scraping at Gree community pages.

=cut

use strict;
use warnings;
use Carp;
use WWW::Mechanize;
use Web::Scraper;

our $VERSION = '0.01';

=head1 CONSTRUCTOR AND STARTUP

=head2 new

Creates and returns a new WebService::Gree::Community object.:

WebService::Gree::Community->new(
#required-
    username => q{YOUR USERNAME},
    password => q{YOUR PASSWORD},
#option
    id    => q{community_id},
);

WebService::AipoLiveオブジェクトの作成

=cut

sub new {
  my $class = shift;
  my %args  = @_;
  $args{agent}      ||= __PACKAGE__." ".$VERSION;
  $args{mech}         = WWW::Mechanize->new(
                            agent => 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:8.0) Gecko/20100101 Firefox/8.0',
                          );
  $args{root}         = 'http://t.gree.jp';
  $args{last_req}  = time;
  $args{interval}  = 3; #sec.
  my $self = bless {%args}, $class;
  $self->login;
  return $self;
}

=head1 METHOD

=head2 login

ログインする

=cut

sub login {
  my $self = shift;
  my $post = {
    action        => 'id_login',
    backto        => '',
    user_mail     => $self->{mail_address},
    user_password => $self->{password},
    login_status  => 1,
  };
  my $res = $self->post($self->{root}, $post);
}

=head2 post

mech post with interval.

=cut

sub post {
  my $self = shift;
  $self->_sleep_interval;
  $self->{'mech'}->post(@_);
}

=head2 get

mech get with interval.

=cut

sub get {
  my $self = shift;
  $self->_sleep_interval;
  $self->{'mech'}->get(@_);
}

=head2 get_members

コミュニティ参加者一覧を取得

=cut

sub get_members {
  my $self = shift;
  my %args = @_;
  $self->{community_id} = $args{id} if $args{id};
  my $members = [];
  my $member_count = $self->_perse_member_count();
  warn $member_count;
  for my $offset (0..$member_count/10){
    my $page_member = $self->_parse_community_members($offset * 10) || [];
    push @$members, @$page_member;
    warn $offset * 10;
    warn join(',', @$page_member);
  }
  return $members;
}

=head1 PRIVATE METHODS.

=over

=item B<_sleep_interval>

アタックにならないように前回のリクエストよりinterval秒待つ。

=cut

sub _sleep_interval {
  my $self = shift;
  my $wait = $self->{interval} - (time - $self->{last_req});
  sleep $wait if $wait > 0;
  $self->{last_req} = time;
}

=item B<_perse_member_count>

参加数を取得

=cut

sub _perse_member_count {
  my $self = shift;

  my $res     = $self->get("@{[$self->{root}]}/?action=community_bbs_list&community_id=@{[$self->{community_id}]}&from_tsns=stream_community&group=community");
  my $content = $res->decoded_content();

  my $scraper = scraper {
    process '//div[@class="txt"]/table[1]/tbody/tr[2]/td', member => 'TEXT';
    result 'member';
  };
  my $result = $scraper->scrape($content);

  #1,000人 の数値のところだけをとって、カンマを取り除く
  $result =~ s/^((\d|,)+)?.*$/$1/;
  $result =~ s/,//g;
  return $result;
}

=item B<_parse_community_members>

ページ内のメンバー ID を取得

=cut

sub _parse_community_members {
  my $self   = shift;
  my $offset = shift;
  my $members = [];
  my $res     = $self->get("@{[$self->{root}]}/?action=community_view_joinlist&community_id=@{[$self->{community_id}]}&group=community&offset=@{[$offset]}&tab=community_members&more=1");
  my $content = $res->decoded_content();
  my $scraper = scraper {
    process '//div[@class="followerList clearfix community_view_joinlist"]', 'members[]' => '@id';
    result 'members';
  };
  my $result = $scraper->scrape($content);
  for my $div_id (@$result){
    $div_id =~ s/community_view_joinlist-//g;
    push @$members, $div_id;
  }
  return $members;
}

1;
__END__

=back

=head1 AUTHOR

Likkradyus E<lt>perl{at}li.que.jpE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
