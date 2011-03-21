# (C) 2011 Pontus Freyhult
# License: GPLv3
#
# Support for tv4play in get-flash-video. This
# adds support for tv4play.se to get_flash_videos.
#
# To add:
#
# get_flash_videos --add-plugin http://github.com/pontus/gfv_svtplay/raw/master/Tv4play.pm
# (If that doesn't work, it may be LWP having problems with gzip content 
#  transfer from github, in that case, it should be fixable by
# 
# cd $HOME/.get_flash_videos/plugins
# gzip -d -c - < Tv4play.pm >Tv4play.pm.fixed 
# mv Tv4play.pm.fixed Tv4play.pm
# 

package FlashVideo::Site::Tv4play;

use strict;

eval { use FlashVideo::Utils };
use WWW::Mechanize::Link;


our @update_urls = (
  'http://github.com/pontus/gfv_svtplay/raw/master/tv4play.pm'
);

sub find_video {
  my ($self, $browser) = @_;

  die "Need XML::Twig for tv4play.se" unless eval { require XML::Twig };

  my $url = 'http://www.tv4play.se/barn/postis_per?title=postis_per_del_6&videoid=1471382';
  # Allow redirection.
  $browser->allow_redirects;
  $browser->get($browser->response->header("Location")) if $browser->response->code =~ /30\d/;

  debug("Parsing page.");

  my $videoid  = ($browser->content =~ /vid=([0-9]*)"/)[0] ;

  debug("Videoid $videoid");

  my $smilurl = "http://anytime.tv4.se/webtv/metafileFlash.smil?p=$videoid&bw=1800";

  debug("Using smil url $smilurl");

  my $data = XML::Twig->new();
  $data->safe_parse($browser->content);

  my $title = extract_title($browser);
  $title =~ s/ *- *TV4 Play *//;
  my $filename = title_to_filename($title);

  $filename ||= get_video_filename();
  debug("Writing to $filename");

  $browser->agent("AppleWebKit/534.9 (KHTML, like Gecko) Ubuntu/9.04 Chromium/7.0.531.0 Chrome/7.0.531.0 Safari/534.9");
  $browser->get($smilurl);
  
  die unless $browser->response->code =~/20\d/;

  $data = XML::Twig->new();
  $data->safe_parse($browser->content);

  my @meta = $data->get_xpath("//meta[\@base]");
  my $base = $meta[0]->{'att'}->{'base'};

  debug("Base url is $base");

  my @video = $data->get_xpath("//video[\@src]");
  my $videourl = $video[0]->{'att'}->{'src'};
  
  debug("Using video path $videourl");

  # Return a structure that is used to construct the rtmpdump command.
  return {
      rtmp => $base,
      playpath =>  $videourl,
      app =>  'tv4ondemand',
      pageUrl => $url,
      flv => $filename,
      resume => '', 
     };
}

1;
