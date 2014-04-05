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
use Text::Trim;

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
    my $community_id = $args{community_id} ? $args{community_id} : $self->{community_id};
    my $members = [];
    my $member_count = $self->_perse_member_count($community_id);
    for my $offset (0..$member_count/10){
        my $page_member = $self->_parse_community_members($community_id, $offset * 10) || [];
        push @$members, @$page_member;
    }
    return $members;
}

=head2 get_bbs_list

コミュニティ内トピック一覧

=cut

sub get_bbs_list {
    my $self = shift;
    my %args = @_;
    my $community_id = $args{community_id} ? $args{community_id} : $self->{community_id};
    my $bbs_list = [];
    my $offset   = 0;
    while (1){
        my $res = $self->get("@{[$self->{root}]}/?community_id=@{[$community_id]}&action=community_bbs_list&more=1&offset=@{[$offset]}");
        my $bbs_list_wk = $self->_parse_bbs_list($res->decoded_content()) || [];
        push @$bbs_list, @$bbs_list_wk;
        last if scalar @$bbs_list_wk < 10;
        $offset += 10;
    }
    return $bbs_list;
}

=head2 show_bbs

bbs内の閲覧

=cut

sub show_bbs {
    my $self = shift;
    my %args = @_;
    my $page = $self->{page} || 1;
    my $community_id = $args{community_id} ? $args{community_id} : $self->{community_id};
    my $thread_id    = $args{thread_id};
    my $offset       = ($page - 1) * 5;
    my $res = $self->get("@{[$self->{root}]}/?community_id=@{[$community_id]}&thread_id=@{[$thread_id]}&action=community_bbs_view&offset=@{[$offset]}");
    $self->_parse_bbs($res->decoded_content);
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
    my $community_id = shift;
    my $res     = $self->get("@{[$self->{root}]}/?action=community_bbs_list&community_id=@{[$community_id]}&from_tsns=stream_community&group=community");
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

ページ内のメンバーID を取得

=cut

sub _parse_community_members {
    my $self   = shift;
    my $community_id = shift;
    my $offset = shift;
    my $members = [];
    my $res     = $self->get("@{[$self->{root}]}/?action=community_view_joinlist&community_id=@{[$community_id]}&group=community&offset=@{[$offset]}&tab=community_members&more=1");
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

=item B<_bbs_list>

トピック一覧のパース

=cut

sub _parse_bbs_list {
    my $self = shift;
    my $html = shift;
    my $bbs_list = [];

    my $scraper = scraper {
        process '//a', 'data[]' => scraper {
            process '//div[@class="txt"]/div[1]/span[@class="userName"]', title       => 'TEXT';
            process '//div[@class="txt"]/div[1]/span[@class="count"]',    count       => 'TEXT';
            process '//div[@class="txt"]//div[@class="description"]',     description => 'TEXT';
            process '//div[@class="txt"]//div[@class="timestamp"]',       timestamp   => 'TEXT';
        };
        process '//a', 'script[]' => '@onclick';
    };
    my $bbs_list_wk = $scraper->scrape($html);
    for my $index (0.. $#{$bbs_list_wk->{data}}){

        #thread_id が onclick に入り込んでるのでそれを取り出してやる
        my $script = $bbs_list_wk->{script}->[$index];
        $script =~ s{^(?:.*)?'thread_id':'(\d+)'(.*)?$}{$1};


        #valueの前後に半角空白が入るので trim してやる
        my $data = $bbs_list_wk->{data}->[$index];
        while(my($k, $v) = each %$data){
            $data->{$k} = trim($v);
        }

        #整形して結果にpush
        push @$bbs_list, {
            %{$data},
            link => $script,
        };
    }
    return $bbs_list;
}

=item B<_parse_bbs>

ﾄﾋﾟｯｸの中身を見るよ

=cut

sub _parse_bbs {
    my $self = shift;
    my $html = shift;
    my $result = [];
    my $scraper = scraper {
        process '//div[@class="comment comment-text community_bbs_view"]', 'divs[]' => scraper {
            process '//div[@class="userName"]/div[@class="nickname"]', user_name => 'TEXT';
            process '//div[@class="comTxt"]',                          description => 'TEXT';
            process '//div[@class="timestamp"]',                       timestamp => 'TEXT';
        }, 'ids[]' => '@id';

    };

    my $data = $scraper->scrape($html);
    my $index = 0;
    #comment_idを取り出す
    my $ids =  [ grep { $_ =~ s{^msg-(\d+)$}{$1} } @{$data->{ids}} ];

    for my $div (@{$data->{divs}}){
        #関係ない div を除去する

        #valueの前後に半角空白が入るので trim してやる
        while(my($k, $v) = each %$div){
            $div->{$k} = trim($v);
        }

        #整形 & comment_id加えつつ結果にpush
        push @$result, {
            %$div,
            id => $ids->[$index],
        };
        $index++;
    }
    $result = [sort {$a->{id} <=> $b->{id} } @$result ];
    return $result;
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
