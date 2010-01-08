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

use Data::Dumper;
use CGI;
use FlashVideo::Utils;
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

  # print $browser->content;

  info("Parsing page.");
  my $data = XML::Twig->new();
  $data->parse($browser->content);
	
  if ($@) {
    die "Error while parsing page: $@";
  }
  

  my @params = $data->get_xpath('//param[@value=~ /pathflv/]');
  my $pathflv = $params[0]->{'att'}->{'value'};

  debug("Extracted flash parameters, parsing");

  my $form = CGI->new($pathflv);
  
  my $rtmppath = $form->param('pathflv');
 
  # folderStructure will contain any series name
  my $series = ($form->param('folderStructure') =~ /(.*)\.Hela program/)[0];
  my $title = $form->param('title');
  my $date = $form->param('broadcastDate');

  my $filename = "$series - $title ($date).flv";
  if ($title == $series) 
  {
# Give a nicer filename for movies
      $filename = "$title ($date).flv";
  }

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
