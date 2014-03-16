#!/usr/bin/env perl
#
#-------------------------------------------------------------------------------
# Traverse perl install directory and look for module files (.pm).
#-------------------------------------------------------------------------------
use Modern::Perl;
use Moose;
use File::Find ();
use Module::Metadata;
use DateTime;
use English;

#-------------------------------------------------------------------------------
# Names of modules found via File::Find and @INC
#
has moduleNames =>
    ( is		=> 'rw'
    , isa		=> 'HashRef'
    , traits		=> ['Hash']
    , default		=> sub { return {}; }
    , handles		=>
      { addModule	=> 'set'
      , getModule	=> 'get'
      , getModuleNames	=> 'keys'
      , existModule	=> 'defined'
      }
    );

# Modules which are processed
#
has processedModules =>
    ( is		=> 'rw'
    , isa		=> 'HashRef'
    , traits		=> ['Hash']
    , default		=> sub { return {}; }
    , handles		=>
      { addPModule	=> 'set'
      , existPModule	=> 'defined'
      }
    );

# Aid for printing
#
has maxModNameLength =>
    ( is		=> 'rw'
    , isa		=> 'Int'
    , default		=> 0
    );

# Aid for printing
#
#has maxPathLength =>
#    ( is		=> 'rw'
#    , isa		=> 'Int'
#    , default		=> 0
#    );

#-------------------------------------------------------------------------------
my $self = main->new();

#-------------------------------------------------------------------------------
# Traverse directories from INC array.
#
File::Find::find( {wanted => sub { $self->getModInfo(@_); }}, @INC);
#File::Find::find( {wanted => sub { $self->getModInfo(@_); }}, $INC[1]);

#-------------------------------------------------------------------------------
# Process result
#
my $runPerlVersion = join( '.', @{$PERL_VERSION->{version}});
open my $ML, '>', "ModuleList.Perl-$runPerlVersion.txt";
my $mxl = $self->maxModNameLength;
#my $mxp = $self->maxPathLength;

my $dateTime = DateTime->now;
$dateTime->set_time_zone('Europe/Amsterdam');
my $date = $dateTime->ymd;
my $time = $dateTime->hms;

say $ML <<EOHEAD;

Module list on system gathered from \@INC using Perl version $runPerlVersion
Date $date $time

Paths from \@INC;
EOHEAD

for( my $i = 0; $i <= $#INC; $i++)
{
  say $ML sprintf "[%02d] %s", $i, $INC[$i];
}

say $ML "";
say $ML ' ' x 11, " +- Module has manual";
say $ML sprintf( "%-11.11s %s %-4s %-${mxl}.${mxl}s"
  	       , 'Version', 'V', 'INC', 'Module name', 'Purpose'
	       );
say $ML '-' x 11, ' -', ' ', '-' x 4, ' ', '-' x $mxl, ' ', '-' x 100;
my $cmpare = sub {lc($a) cmp lc($b);};
foreach my $pk (sort $cmpare $self->getModuleNames)
{
  my $m = $self->getModule($pk);

  say $ML sprintf( "%-11.11s %s %4s %-${mxl}.${mxl}s %s"
  		 , $m->{version}, $m->{manual}
		 , $m->{path}, $pk, $m->{purpose}
		 );
}

close $ML;

exit(0);

################################################################################
#
sub getModInfo
{
  my( $self) = @_;

  # Skip all files other than module files or modules from the current directory
  #
  return if $File::Find::dir eq '.';
  my $package = $File::Find::name;
  return unless $package =~ /\.pm$/;

  # Remove extension
  #
  $package =~ s@\.pm$@@;

  # When running a perl version with perlbrew then there is another path used
  # for the libraries
  #
  my $runPerlVersion = join( '.', @{$PERL_VERSION->{version}});
  $package =~ s@^.+?/$runPerlVersion/lib/@@;
  $package =~ s@^.*?/x86_64-linux-thread-multi/@@;

  # Remove parts from path
  #
  $package =~ s@^.+?perl5/@@;
  $package =~ s@^.*?vendor_perl/@@;
  $package =~ s@^.*?sys/@@;
  $package =~ s@^.*?auto/@@;
  $package =~ s@^.*?site/@@;
  $package =~ s@^.*?build/@@;

  # Modify path / into module :: separator.
  #
  $package =~ s@/@::@g;

  my $mPk = $self->processInfo($package);
  $self->addModule( $package => $mPk) if defined $mPk;
  $self->addPModule( $package => 1);
}

################################################################################
# Get information about a package/module
#
sub processInfo
{
  my( $self, $package) = @_;

  # Initialize default info
  #
  my $m = { manual => '-'
  	  , version => ''
	  , provides => []
	  , purpose => ''
	  , path => ''
	  };

  # Return if found before
  #
  return undef if $self->existPModule($package);

  # Save maximum length of modulenames for printing later
  #
  my $l = length($package);
  $self->maxModNameLength($l) if $l > $self->maxModNameLength;

  # Get meta information but return defaults when there isn't any
  #
  my $meta = Module::Metadata->new_from_module( $package, collect_pod => 1);
  return $m unless defined $meta;

  # Get the version and manual
  #
  $m->{version} = $meta->version ? $meta->version : '';
  $m->{manual} = $meta->contains_pod ? 'M' : ' ';
  
  # Get path to module, replace INC search path with a number to make it shorter
  #
  my $path = $meta->filename;
  for( my $i = 0; $i <= $#INC; $i++)
  {
    if( $path =~ m/$INC[$i]/ )
    {
      $path = sprintf "[%02d]", $i;
#      $path =~ s/$INC[$i]/$str/;
      last;
    }
  }
  $m->{path} = $path;

  # Save maximum length of path for printing later
  #
#  $l = length($path);
#  $self->maxPathLength($l) if $l > $self->maxPathLength;

  # Get the purpose line from the documentation
  #
  my $pod = $meta->pod('NAME');
  if( defined $pod )
  {
    $m->{purpose} = $m->{manual} eq 'M' ? $pod : '';
    $m->{purpose} =~ s/\n//g;
    $m->{purpose} =~ s/$package -\s*//;
  }

  # Get packages inside this one and process recursively
  #
  my @pkpms = $meta->packages_inside;
  $m->{provides} = [];
  foreach my $pkpm (@pkpms)
  {
    next if $pkpm eq $package;
    push @{$m->{provides}}, $pkpm;

    # Make a note that it is found to prevent infinite re(curse). It is
    # checked at the beginning of the function.
    #
    $self->addPModule( $pkpm => 1);
    
    # Process module and add info
    #
    my $mPkpm = $self->processInfo($pkpm);
    $self->addModule( $pkpm => $mPkpm) if defined $mPkpm;
  }
  
  $m->{infoProcessed} = 1;
  return $m;
}


