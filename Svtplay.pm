# (C) 2010 Pontus Freyhult
# License: GPLv3
#
# Support for SVT play in get-flash-video. This
# adds support for svtplay.se to get_flash_videos.
#
# To add:
#
# get_flash_videos --add-plugin http://github.com/pontus/gfv_svtplay/raw/master/Svtplay.pm


package FlashVideo::Site::Svtplay;

use strict;

use CGI;
eval { use FlashVideo::Utils };
use WWW::Mechanize::Link;


our @update_urls = (
  'http://github.com/pontus/gfv_svtplay/raw/master/Svtplay.pm'
);

sub find_video {
  my ($self, $browser) = @_;

  die "Need XML::Twig for svtplay.se" unless eval { require XML::Twig };

  # Allow redirection.
  $browser->allow_redirects;
  $browser->get($browser->response->header("Location")) if $browser->response->code =~ /30\d/;

  debug("Parsing page.");
  my $data = XML::Twig->new();
  $data->parse($browser->content);
	
  if ($@) {
    die "Error while parsing page: $@";
  }
  

  if ($data->get_xpath('//rss'))
  {
      my @links = $data->get_xpath('//item/link');
      my $pageurl = $links[0]->xml_text();
      # Feed actually contains a lot of extra info we could use, but
      # for the moment, we're satisfied with what we normally get.
      debug("Page from RSS, going through to normal page $pageurl. ");
      
      $browser->get($pageurl);
      return find_video($self,$browser);
  }

  my @params = $data->get_xpath('//param[@value=~ /pathflv/]');
  my $pathflv = $params[0]->{'att'}->{'value'};

  debug("Extracted flash parameters, parsing");

  my $form = CGI->new($pathflv);
  my $rtmppath = $form->param('pathflv');

  # Handle errorneous URLs with $junk attached.
  if ($rtmppath =~ /\$/)
  {
      # Get everything before $
      $rtmppath = ($rtmppath =~ /([^\$]*)\$/)[0];
  }

  # folderStructure will contain any series name
  my $series = ($form->param('folderStructure') =~ /(.*)\.Hela program/)[0];
  my $title = $form->param('title');
  my $date = $form->param('broadcastDate');

  my $filename = "$series - $title ($date).flv";
  if ($title eq $series) 
  {   # Give a nicer filename for movies
      $filename = "$title ($date).flv";
  }

  # Replace some characters not allowed in filenames.
  $filename =~ s,[/:\\],-,g;

  info("Fetching $title, originally aired $date.\n" .
       "Using URL: $rtmppath\n");
  
  # Extract the first non host parts of the url as app
  # my $rtmppath = "rtmp://testhost/testapp1/testapp2/playpath";
  my $app = ($rtmppath =~ m,//.*?/([^/]*?/[^/]*?)/,)[0];

  debug("Deducing app $app from rtmp path $rtmppath\n");

  # Return a structure that is used to construct the rtmpdump command.
  return {
      app =>  $app,
      pageUrl => $form->param('urlinmail'),
      tcUrl => $rtmppath,
      rtmp => $rtmppath,
      flv => $filename,
     };
}

1;
