package WebService::Gree::Community;

=head1 NAME

WebService::Gree::Community - Gree community info.

=head1 SYNOPSIS

  use WebService::Gree::Community;
  my $gree = WebService::Gree::Community->new(
    mail_address  => 'your mail_address',
    password      => 'your password',
    community_id  => 000000,
  );
  my $bbs_list = $gree->show_bbs_list;
  use YAML;
  print YAML::Dump $bbs_list;

=head1 DESCRIPTION

WebService::Gree::Community is scraping at community pages in Gree.

=cut

use strict;
use warnings;
use utf8;
use 5.10.0;
use Carp;
use HTTP::Date;
use WWW::Mechanize;
use Web::Scraper;
use Text::Trim;
use YAML;

=head1 GLOBAL VARIABLE

=head2 VERSION

this is version of this package.

=head2 GUESS_YEAR

西暦データが取れないので発言IDなどから推測する

=cut

our $VERSION    = '2.00';
our $GUESS_YEAR = 0;

=head1 CONSTRUCTOR AND STARTUP

=head2 new

Creates and returns a new WebService::Gree::Community object.:

WebService::Gree::Community->new(
#required
    username => q{YOUR USERNAME},
    password => q{YOUR PASSWORD},
#option
    id    => q{community_id},
);

WebService::Gree::Community オブジェクトの作成

=cut

sub new {
    my $class = shift;
    my %args  = @_;

    my $self = bless { %args }, $class;
    $self->login();
    return $self;
}

=head1 ACCESSOR

=head2 conf

configure at free.net

=cut

#XXX: WebService::Gree::URI とか作ってそこに逃すべき
sub conf {
    my $self = shift;
    return $self->{conf} ||= do {
        my $conf = {
            origin      => 'secure.gree.jp',
        };
        $conf->{login_url}      = sub { sprintf("https://%s/",  $conf->{origin}) };
        $conf->{community_top}  = sub { sprintf("http://%s/community/%s", $conf->{origin}, shift) };
        $conf->{bbs_list}       = sub {
            my ($community_id, $offset) = @_;
            sprintf("http://%s/?mode=community&act=bbs_list&community_id=%s&offset=%s&limit=20", $conf->{origin}, $community_id, $offset);
        };
        $conf->{bbs_view}            = sub {
            my $thread_id = shift;
            my $offset    = shift // 0;
            sprintf("http://%s/?mode=community&act=bbs_view&thread_id=%s&offset=%s&limit=20", $conf->{origin}, $thread_id, $offset);
        };

        $self->{conf} = $conf;
    }
}

=head2 mech

use WWW::Mechanize object

=cut

sub mech {
    my $self = shift;
    unless($self->{mech}){
        my $mech = WWW::Mechanize->new(
            agent      => 'Mozilla/5.0 (Windows NT 6.1; rv:28.0) Gecko/20100101 Firefox/28.0',
            cookie_jar => {},
        );
        $mech->stack_depth(10);
        $self->{mech} = $mech;
    }
    return $self->{mech};
}

=head2 interval

sleeping time per one action by Mech.

=head2 last_request_time

request time at last;

=cut

sub interval          { return shift->{interval} ||= 1    }
sub last_request_time { return shift->{last_req} ||= time }
sub guess_year        {
    my $self = shift;
    my $w    = shift;
    if(defined $w){
        $GUESS_YEAR = $w;
    }
    return $GUESS_YEAR;
}

=head1 METHOD

=head2 set_last_request_time

set request time

=cut

sub set_last_request_time { shift->{last_req} = time }

=head2 post

mech post with interval.

=cut

sub post {
    my $self = shift;
    $self->_sleep_interval;
    $self->mech->post(@_);
}

=head2 get

mech get with interval.

=cut

sub get {
    my $self = shift;
    $self->_sleep_interval;
    $self->mech->get(@_);
}

=head2 login

ログインする

=cut

sub login {
    my $self = shift;
    my $login_url = $self->conf->{login_url};

    my $res  = $self->get($login_url->());
    my $content = $self->mech->content;

    my ($tok, $etok);
    if($content =~m{<input\stype="hidden"\sname="csrf\[etok\]"\svalue="(.*?)"\s/>}){
        $etok = $1;
    }
    if($content =~m{<input\stype="hidden"\sname="csrf\[tok\]"\svalue="(.*?)"\s/>}){
        $tok = $1;
    }

    my $post = {
        mode             => 'common',
        act              => 'login',
        backto           => '',
        campaign_code    => '',
        'csrf[tok]'      => $tok,
        'csrf[etok]'     => $etok,
        user_mail        => $self->{mail_address},
        user_password    => $self->{password},
        login_status     => 1,
        submit           => 'ログイン',
    };

    $self->mech->post($login_url->(), $post);
    $content =  $self->mech->content;
    die 'cant login' if Encode::encode_utf8($content) =~ /ログインが完了しました。/;
}


=head2 get_members

コミュニティ参加者一覧を取得

=cut

sub get_members {
    die 'sorry, this method is not updated.';
}

=head2 get_bbs_list

コミュニティ内トピック一覧

=cut

sub get_bbs_list {
    my $self = shift;
    my %args = @_;
    my $community_id = $args{community_id} ? $args{community_id} : $self->{community_id};
    $self->get($self->conf->{community_top}($community_id));

    my $bbs_list = [];
    my $offset   = 0;
    while (1){
        my $url = $self->conf->{bbs_list}($community_id, $offset);
        my $res = $self->get($url);
        my $bbs_list_wk = $self->_parse_bbs_list($res->decoded_content()) || [];
        push @$bbs_list, @$bbs_list_wk;

        #bbs_list が20の時だけ、次のページを呼び出す
        #取れない、若しくは20未満の場合は次のページはない
        #20を越えた時はそもそもパースがおかしい
        last unless    scalar @$bbs_list_wk == 20;
        $offset += 20;
    }
    $bbs_list = [ sort {$b->{thread_id} <=> $a->{thread_id} }  @$bbs_list ];

    if($self->guess_year){
        my $epoch = time;
        my $lt    = [ localtime($epoch) ];
        for my $row (@$bbs_list){
            #西暦データで取れないので仮で埋めていく
            #取れるデータは月日時分 ###exp 4/10 12:12
            #秒は0固定、年は一旦今年を入れる。
            #現在時刻より未来になってしまうのであれば、それは去年以前と推測されるが一律で去年という扱いにする。
            my $year  = $lt->[5] + 1900;
            while(1){
                my $view_date  = $row->{view_date};
                $view_date     =~ s{/}{-}g;
                my $guess_date = sprintf("$year-%s:00 +9:00", $view_date);
                $guess_date    =~ s{-(\d{1})-}{-0$1-};
                $guess_date    =~ s{-(\d{1}) }{-0$1 };
                my $time       = HTTP::Date::str2time($guess_date);
                if($epoch > $time){
                    #$epoch = $time;
                    $row->{epoch}     = $time;
                    $row->{timestamp} = HTTP::Date::time2iso($time);
                    last;
                }
                $year--;
                die 'something wrong year.' if $year < 2004 #greeができるより前の年になるのは何かおかしい
            }
        }
        $bbs_list = [ sort {$b->{epoch} <=> $a->{epoch} }  @$bbs_list ];
    }

    return $bbs_list;
}

=head2 show_bbs

bbs内の閲覧

=cut

sub show_bbs {
    my $self = shift;
    my %args = @_;
    my $page = $self->{page} // 0;
    my $thread_id    = $args{thread_id};
    my $offset       = $page  * 20;
    my $url = $self->conf->{bbs_view}($thread_id, $offset);
    my $res = $self->get($url);
    $self->_parse_bbs($res->decoded_content);
}

=head1 PRIVATE METHODS.

=over

=item B<_sleep_interval>

アタックにならないように前回のリクエストよりinterval秒待つ。

=cut

sub _sleep_interval {
    my $self = shift;
    my $wait = $self->interval - (time - $self->last_request_time);
    sleep $wait if $wait > 0;
    $self->set_last_request_time();
}

=item B<_perse_member_count>

参加数を取得

=cut

sub _perse_member_count      { die 'sorry, this method is not updated.'; }

=item B<_parse_community_members>

ページ内のメンバーID を取得

=cut

sub _parse_community_members {  die 'sorry, this method is not updated.'; }

=item B<_bbs_list>

トピック一覧のパース

=cut

sub _parse_bbs_list {
    my $self = shift;
    my $html = shift;
    my $bbs_list = [];
    my $scraper = scraper {
        process '//ul[@class="feed-list clearfix"]/li', 'data[]' => scraper {
            process '//div[@class="item"]/div[@class="head"]',                              head      => 'TEXT';
            process '//div[@class="item"]/div[@class="head"]/a',                            url       => '@href';
            process '//div[@class="item"]/div[@class="response"]/span[@class="timestamp"]', view_date => 'TEXT';
        };
    };
    my $bbs_list_wk = $scraper->scrape($html)->{data};
    $bbs_list_wk = [ grep { keys %$_; } @$bbs_list_wk ];
    for my $row (@$bbs_list_wk){

        my $head = $row->{head};
        my @title_wk = split /（/, $head;
        my $count    = pop @title_wk;
        chop($count);
        my $title    = join('', @title_wk);

        my $thread_id = [split /=/,$row->{url}]->[-1];

        #整形して結果にpush
        push @$bbs_list, {
            title     => $title,
            count     => $count,
            view_date => $row->{view_date},
            'link'    => $row->{url},
            thread_id => $thread_id,
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
    my $scraper = scraper {
        process '//div[@id="comment-list"]/ul[@class="comment-list"]/li', 'comments[]' => scraper {
            process '*', id => '@id';
            process '//div[@class="item"]/strong',                      user_name => 'TEXT';
            process '//div[@class="item"]/strong/a',                    user_link => '@href';
            process '//div[@class="shoulder"]/span[@class="timestamp"]', view_date => 'TEXT';
            process '//div[@class="item"]',                             raw_data  => 'TEXT';
        };
        result 'comments';
    };
    my $data = $scraper->scrape($html);

    for my $row (@$data){
        next unless $row->{id};
        #user_id を リンクから抽出する
        if($row->{user_id} = $row->{user_link}){
            if($row->{user_id} =~ /.*?(\d+)?$/){
                $row->{user_id} = $1;
            }
        }

        #日付時刻以降が本文なので、それを抽出する
        if($row->{description} = $row->{raw_data}){
            $row->{description} = [ split m{\d{1,2}/\d{1,2}\s\d{1,2}:\d{1,2}}, $row->{description} ]->[1];
            #raw_data は要らない子
            delete $row->{raw_data};
        }
    }

    my $result = [
        sort {
            $b->{id} <=> $a->{id}
        }
        grep {
            defined $_->{id}
        }
        @$data
    ];


    #bbs_id順にsort
    if($self->guess_year){
        my $epoch = time;
        my $lt    = [ localtime($epoch) ];
        for my $row (@$result){
            #西暦データで取れないので仮で埋めていく
            #取れるデータは月日時分 ###exp 4/10 12:12
            #秒は0固定、年は一旦今年を入れる。
            #現在時刻より未来になってしまうのであれば、それは去年以前と推測されるが一律で去年という扱いにする。
            my $year  = $lt->[5] + 1900;
            while(1){
                my $view_date  = $row->{view_date};
                $view_date     =~ s{/}{-}g;
                my $guess_date = sprintf("$year-%s:00 +9:00", $view_date);
                $guess_date    =~ s{-(\d{1})-}{-0$1-};
                $guess_date    =~ s{-(\d{1}) }{-0$1 };
                my $time       = HTTP::Date::str2time($guess_date);
                if($epoch > $time){
                    #$epoch = $time;
                    $row->{epoch}     = $time;
                    $row->{timestamp} = HTTP::Date::time2iso($time);
                    last;
                }
                $year--;
                die 'something wrong year.' if $year < 2004 #greeができるより前の年になるのは何かおかしい
            }
        }
        $result = [ sort {$b->{epoch} <=> $a->{epoch} }  @$result ];
    }

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
