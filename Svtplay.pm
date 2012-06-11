# (C) 2010 Pontus Freyhult
# License: GPLv3
#
# Support for SVT play in get-flash-video. This
# adds support for svtplay.se to get_flash_videos.
#
# To add:
#
# get_flash_videos --add-plugin http://github.com/pontus/gfv_svtplay/raw/master/Svtplay.pm
# (If that doesn't work, it may be LWP having problems with gzip content 
#  transfer from github, in that case, it should be fixable by
# 
# cd $HOME/.get_flash_videos/plugins
# gzip -d -c - < Svtplay.pm >Svtplay.pm.fixed 
# mv Svtplay.pm.fixed Svtplay.pm
# 

package FlashVideo::Site::Svtplay;

use strict;

use CGI;
eval { use FlashVideo::Utils };
use WWW::Mechanize::Link;
use WWW::Mechanize;

our @update_urls = (
  'http://github.com/pontus/gfv_svtplay/raw/master/Svtplay.pm'
);

sub find_video {
  my ($self, $browser) = @_;

  die "Need XML::Twig for svtplay.se" unless eval { require XML::Twig };
  die "Need JSON for svtplay.se" unless eval { require JSON };

  # Allow redirection.
  $browser->allow_redirects;
  $browser->get($browser->response->header("Location")) if $browser->response->code =~ /30\d/;

  my $page = $browser->content;

  # Program main page, which we should add embed to?
  if ($page =~ /data-popout-href/)
  {

      my $pageurl = $browser->uri() . '?type=embed';
      $browser->get($pageurl);
      debug("Program main page, redoing for $pageurl");
      return find_video($self,$browser);
  }

  # 
 
  my $data = XML::Twig->new();

  debug("Parsing page.");

  my $ok = $data->safe_parse($page);

  if (!$ok) {

      debug("Error while parsing page: $@");
      debug("Will try to fix some HTML issues and retry");

      # Repair broken html
      $page =~ s/<link[^>]*>//g;
      $page =~ s/<meta[^>]*>//g;
      $page =~ s/<img[^>]*>//g;
      $page =~ s/<input[^>]*>//g;
      $page =~ s/document.write([^)]*)//;

      my $ok = $data->safe_parse($page);
      
      if (!$ok) 
      {
	  die "Fatal error while parsing page, even after fixing HTML: $@";
      }
  }
  
  # $data (Twig) should be okay here


  if ($data->get_xpath('//rss'))
  {
      # We've got a page from a feed?
      my @mediacontents = $data->get_xpath('//media:content');
      my @subtitle = $data->get_xpath('//media:subTitle');
      my @titleString = $data->get_xpath('//media:title');
      my $filename;

      my $rtmppath = undef;
      my $bitrate = 0;

      if (@titleString)
      {
	  $filename = @titleString[0]->children_text() . ".flv";
	  # Replace some characters not allowed in filenames.
	  $filename =~ s,[/:\\],-,g;

	  debug("Filename: $filename");
      }
      
      if (@subtitle)
      {
	  debug("We should download " . @subtitle[0]->{'att'}->{'href'});
      
	  my $suffix = (@subtitle[0]->{'att'}->{'href'} =~ s/.*\.//r);
	  my $subfilename = ($filename =~ s/flv$//r) . $suffix ;

	  info ("Getting subtitlefile.");
	  debug("$subfilename $suffix "  . @subtitle[0]->{'att'}->{'href'});
	  # Get the file, do some magic to not have a gzip file.
	  my $mech = WWW::Mechanize->new;
	  $mech->add_header( 'Accept-Encoding' => undef );
	  $mech->get( @subtitle[0]->{'att'}->{'href'},
		     ":content_file" => $subfilename);
	  
      }
      

      foreach my $content (@mediacontents)
      {
	  if ( $content->{'att'}->{'bitrate'} > $bitrate && 
	       $content->{'att'}->{'type'} == "video/mp4")
	  {
	      $bitrate = $content->{'att'}->{'bitrate'};
	      $rtmppath = $content->{'att'}->{'url'};

	      debug ("Bitrate: " . $bitrate  . " URL: " . $rtmppath);
	  } 
      }

	  if ($rtmppath) 
	  {
	      my $app = ($rtmppath =~ m,//.*?/([^/]*?/[^/]*?)/,)[0];

	      return
	       {
		  app =>  $app,
		  pageUrl => $mediacontents[0]->first_child("media:player")->{'att'}->{'url'},
		  tcUrl => $rtmppath,
		  rtmp => $rtmppath,
		  flv => $filename,
		  resume => '',
	      };

	  }


      my @links = $data->get_xpath('//item/link');
      my $pageurl = $links[0]->xml_text();

      debug("Page from RSS but no good URLs, going through to normal page $pageurl. ");
      
      $browser->get($pageurl);
      return find_video($self,$browser);
  }

  my $rtmppath;

  my @params = $data->get_xpath('//param[@name=~ /flashvars/]');

  if (!@params )
  {
      die "Failed when extracting flash player parameters. This should not happen!";
  }
  
  
  my $pathflv = $params[0]->{'att'}->{'value'};
  
  $pathflv =~ s/^json=//;
  
  debug("Extracted flash parameters, parsing");
  

  my $json = JSON->new->utf8->decode($pathflv);      
  
  debug("JSON: " . $json->{context}->{title}); 

  my $filename = $json->{statistics}->{title} . ".flv";

  # Replace some characters not allowed in filenames.
  $filename =~ s,[/:\\],-,g;


  my $bitrate=0;
  
  foreach my $videoref (@{$json->{video}->{videoReferences}}) 
  {
      if ($videoref->{playerType} == "flash" && $videoref->{bitrate} > $bitrate)
      {
	  $rtmppath = $videoref->{url};
	  $bitrate = $videoref->{bitrate};
	  debug ("Path: $rtmppath with bitrate $bitrate" );
      }
  }

  if (exists $json->{video}->{subtitleReferences})
  {
      debug("We should download " . $json->{video}->{subtitleReferences}[0]->{url});
      
      my $suffix = ($json->{video}->{subtitleReferences}[0]->{url} =~ s/.*\.//r);

      my $subfilename = ($filename =~ s/flv$//r) . $suffix ;

      info ("Getting subtitlefile.");

      # Get the file, do some magic to not have a gzip file.
      my $mech = WWW::Mechanize->new;
      $mech->add_header( 'Accept-Encoding' => undef );
      $mech->get($json->{video}->{subtitleReferences}[0]->{url},
		 ":content_file" => $subfilename);
  }


  info("Fetching " . $json->{context}->{title} . ", originally aired " . $json->{statistics}->{broadcastDate} . ".\n" .
       "Using URL: $rtmppath\n");
  
  # Extract the first non host parts of the url as app
  # my $rtmppath = "rtmp://testhost/testapp1/testapp2/playpath";
  my $app = ($rtmppath =~ m,//.*?/([^/]*?/[^/]*?)/,)[0];

  debug("Deducing app $app from rtmp path $rtmppath\n");

  # Return a structure that is used to construct the rtmpdump command.
  return {
      app =>  $app,
      pageUrl => "http://www.svtplay.se" .$json->{context}->{popoutUrl},
      tcUrl => $rtmppath,
      rtmp => $rtmppath,
      flv => $filename,
      resume => '',
     };
}

1;
