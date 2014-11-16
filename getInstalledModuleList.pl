#!/usr/bin/env perl
#
#-------------------------------------------------------------------------------
# Traverse perl install directory and look for module files (.pm).
#-------------------------------------------------------------------------------
use Modern::Perl;
use version; my $VERSION = version->parse('v2.3.0');
use Moose;
use File::Find ();
use Module::Metadata;
use DateTime;
use English qw(-no_match_vars); # Avoids regex perf penalty, perl < v5.016000
use Module::CoreList 2.99 ();
require match::simple;
use File::Grep qw(fgrep);

#-------------------------------------------------------------------------------
# Names of modules found via File::Find and @INC
#
has moduleNames =>
    ( is                => 'rw'
    , isa               => 'HashRef'
    , traits            => ['Hash']
    , default           => sub { return {}; }
    , handles           =>
      { setModule       => 'set'
      , getModule       => 'get'
      , getModuleNames  => 'keys'
      , existModule     => 'defined'
      }
    );

has rpm_modules =>
    ( is                => 'rw'
    , isa               => 'HashRef'
    , traits            => ['Hash']
    , default           => sub { return {}; }
    , handles           =>
      { set_rpm_module  => 'set'
      , get_rpm_module  => 'get'
      }
    );

# Modules which are processed
#
has processedModules =>
    ( is                => 'rw'
    , isa               => 'HashRef'
    , traits            => ['Hash']
    , default           => sub { return {}; }
    , handles           =>
      { addPModule      => 'set'
      , existPModule    => 'defined'
      }
    );

# Aid for printing
#
has maxModNameLength =>
    ( is                => 'rw'
    , isa               => 'Int'
    , default           => 0
    );

# Aid for printing
#
#has maxPathLength =>
#    ( is               => 'rw'
#    , isa              => 'Int'
#    , default          => 0
#    );

#-------------------------------------------------------------------------------
my $self = main->new();
my @INC_DATA = @INC;

#-------------------------------------------------------------------------------
# Get perl rpm modules
#
open my $rpm_h, '-|', '/usr/bin/rpm -qa';
while( my $rpm_package = <$rpm_h> )
{
  chomp $rpm_package;
  my $rpm_module = $rpm_package;

  # Remove the perl- prefix first. All perl RPM sources have this on Fedora.
  # Then remove all tekst following the version number.
  #
  next unless $rpm_module =~ m/^perl-/;
  $rpm_module =~ s/^perl-//;
  $rpm_module =~ s/-\d.*$//;

#  my $rpm_module_file = $rpm_module;
#  $rpm_module_file =~ s@-@/@g;

  # Turn into a package name
  #
  $rpm_module =~ s/-/::/g;

  # Keep this name as the package module name (R).
  #
  $self->set_rpm_module($rpm_module => 'R');

  # Read the content of the rpm distribution
  #
  open my $rpm_list_h, '-|', "/usr/bin/rpm -ql $rpm_package";
  while( my $rpm_file = <$rpm_list_h> )
  {
    chomp $rpm_file;
    
    # Only the module files (.pm) are interresting
    # Remove the .pm extention.
    #
    next unless $rpm_file =~ m/\.pm$/;
    $rpm_file =~ s/\.pm//;
    
    # Find out which path the from the INC array is used and remove that part
    # from the file path to keep the package name.
    #
    foreach my $inc (@INC_DATA)
    {
      next if $inc eq '.';

      if( $rpm_file =~ m/^$inc/ )
      {
        $rpm_file =~ s/^$inc\///;
        last;
      }
    }

    # Modify this name into a proper package name
    #
    $rpm_file =~ s@/@::@g;

    # If name matches the end of the package name it is the module base package.
    # A bit of hassle here, The perl-LDAP-.... distribution provides Net::LDAP.
    # So not all of the package name is used always in the distribution name.
    #
    if( $rpm_file =~ m/$rpm_module$/ )
    {
      $self->set_rpm_module($rpm_file => 'R');
    }

    # All other modules found in the distribution will have 'r'.
    #
    elsif( $rpm_file ne $rpm_module )
    {
      $self->set_rpm_module($rpm_file => 'r');
    }
  }
  
  close $rpm_list_h;
}

close $rpm_h;

#-------------------------------------------------------------------------------
# Traverse directories from INC array.
#
for( my $idx = 0; $idx < @INC_DATA; $idx++)
{
  next if $INC_DATA[$idx] eq '.'; # or $INC_DATA[$idx] =~ m/vendor_perl$/;

  say "Search path $INC_DATA[$idx]";

  $File::Find::prune = 1;
  File::Find::find( {wanted => sub { $self->getModInfo( @_, $idx); }}
                  , $INC_DATA[$idx]
                  );
}

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

for( my $idx = 0; $idx <= $#INC; $idx++)
{
  next if $INC_DATA[$idx] eq '.'; # or $INC_DATA[$idx] =~ m/vendor_perl$/;
  say $ML sprintf "[%02d] %s", $idx, $INC_DATA[$idx];
}

say $ML "";
#say $ML ' ' x 14, " +--- Module load error(!)";
say $ML ' ' x 14, " +----- Packages inside module(P)";
say $ML ' ' x 14, " |+---- RPM Module extends perl(R/r)";
say $ML ' ' x 14, " ||+--- Module extends perl(X)";
say $ML ' ' x 14, " |||+-- Perl Core Module(C)";
say $ML ' ' x 14, " ||||+- Module has manual(M)";
say $ML sprintf( "%-14.14s %s %-7s %-${mxl}.${mxl}s"
               , 'Version', 'VVVVV', 'INC', 'Module name', 'Purpose'
               );
say $ML '-' x 14, ' -----', ' ', '-' x 7, ' ', '-' x $mxl, ' ', '-' x 100;
my $cmpare = sub {lc($a) cmp lc($b);};
foreach my $pk (sort $cmpare $self->getModuleNames)
{
  my $m = $self->getModule($pk);

  say $ML sprintf( "%-14.14s %1s%1s%1s%1s%1s %-7s %-${mxl}.${mxl}s %s"
#                 , scalar(@{$m->{version}}) ? $m->{version}->[0] : ''
                 , join( ' ', @{$m->{version}})
#                 , $m->{load_error}
                 , $m->{packaged}
                 , $m->{rpm_module}
                 , $m->{extended}
                 , $m->{core_module}
                 , $m->{manual}
                 , scalar(@{$m->{path}}) ? join( ' ', @{$m->{path}}) : ' '
                 , $pk
                 , $m->{purpose}
                 );
}

close $ML;

exit(0);

################################################################################
#
sub getModInfo
{
  my( $self, $search_path_idx) = @_;

  my $search_path = $INC_DATA[$search_path_idx];


  # Skip all files other than module files or modules from the current directory
  #
#  return if $File::Find::dir eq '.';
  my $file = $File::Find::name;
  $File::Find::prune = 1 if $file =~ m/^.*vendor_perl\z/s
                         and $search_path !~ m/^.*vendor_perl\z/s
                         ;
  say "Skip directory $file" if $File::Find::prune;

  my $package = $file;
  return unless $package =~ /\.pm$/;

#  say "$package";

  # Remove extension and search path
  #
  $package =~ s@\.pm$@@;
  $package =~ s@^$search_path/@@;

  # When running a perl version with perlbrew then there is another path used
  # for the libraries
  #
#  my $runPerlVersion = join( '.', @{$PERL_VERSION->{version}});
#  $package =~ s@^.+?/$runPerlVersion/lib/@@;
#  $package =~ s@^.*?/x86_64-linux-thread-multi/@@;

  # Remove parts from path
  #
#  $package =~ s@^.+?perl5/@@;
  $package =~ s@^.*?vendor_perl/@@;

#  $package =~ s@^.*?sys/@@;
  $package =~ s@^.*?auto/@@;
  $package =~ s@^.*?site/@@;
  $package =~ s@^.*?build/@@;

  # Modify path / into module :: separator.
  #
  $package =~ s@/@::@g;

  my $mPk = $self->processInfo( $package, $search_path_idx, $file);
  $self->setModule( $package => $mPk) if defined $mPk;
#  $self->addPModule( $package => 1);
}

################################################################################
# Get information about a package/module
#
sub processInfo
{
  my( $self, $package, $search_path_idx, $file) = @_;

  # Initialize default info
  #
  my $m = $self->getModule($package);
  $m //= { manual => ''
         , version => []
         , provides => []
         , purpose => ''
         , path => []
         , infoProcessed => 0
         , core_module => ''
         , load_error => ''
         , extended => ''
         , rpm_module => ''
         , packaged => ''
         };


  # Return if found before
  #
#  return undef if $self->existPModule($package);

  # Save maximum length of modulenames for printing later
  #
  my $l = length($package);
  $self->maxModNameLength($l) if $l > $self->maxModNameLength;

  push @{$m->{path}}, $search_path_idx
    unless match::simple::match( $search_path_idx, $m->{path});

  # Get meta information but return defaults when there isn't any
  #
  my $meta = Module::Metadata->new_from_file( $file, collect_pod => 1);
  return $m unless defined $meta;

  # Get the version, manual and other items
  #
  push @{$m->{version}}, $meta->version // '';
  $m->{manual} = $meta->contains_pod ? 'M' : ' ' unless $m->{manual};
  $m->{core_module} = 'C' if Module::CoreList::is_core($package);
  $m->{extended} = 'X' if $file and fgrep {/\b(XSLoader|DynaLoader)\b/} $file;
  $m->{rpm_module} = $self->get_rpm_module($package) // '';

if(0)
{
  if( !$m->{core_module} )
  {
    eval("require $package");   # crashes!
    if( my $err = $@ )
    {
      $m->{load_error} = '!';
    }
  }
}

  # Get the purpose line from the documentation
  #
  my $pod = $meta->pod('NAME');
  if( !$m->{purpose} and defined $pod )
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
#    $self->addPModule( $pkpm => 1);

    my $mp = $self->getModule($pkpm)
           // { manual => ''
              , version => []
              , provides => []
              , purpose => ''
              , path => []
              , infoProcessed => 0
              , core_module => ''
              , load_error => ''
              , extended => ''
              , rpm_module => ''
              , packaged => ''
              };
    my $l = length($pkpm);
    $self->maxModNameLength($l) if $l > $self->maxModNameLength;

    push @{$mp->{path}}, $search_path_idx
      unless match::simple::match( $search_path_idx, $mp->{path});

    # Get meta information but return defaults when there isn't any
    #
    my $module_path = "$INC_DATA[$search_path_idx]/$pkpm";
    $module_path =~ s/::/\//g;
    my $meta = Module::Metadata->new_from_file( $module_path, collect_pod => 1);
    next unless defined $meta;

    # Get the version, manual and other items
    #
    push @{$mp->{version}}, $meta->version // '';
    $mp->{manual} = $meta->contains_pod ? 'M' : ' ' unless $mp->{manual};
    $mp->{core_module} = 'C' if Module::CoreList::is_core($pkpm);
#    $mp->{extended} = 'X' if $file and fgrep {/\b(XSLoader|DynaLoader)\b/} $file;
    $mp->{packaged} = 'P';
    $m->{rpm_module} = $self->get_rpm_module($pkpm) // '';

    # Get the purpose line from the documentation
    #
    my $pod = $meta->pod('NAME');
    if( !$mp->{purpose} and defined $pod )
    {
      $mp->{purpose} = $mp->{manual} eq 'M' ? $pod : '';
      $mp->{purpose} =~ s/\n//g;
      $mp->{purpose} =~ s/$pkpm -\s*//;
    }

    $self->setModule( $pkpm => $mp);
  }

  $m->{infoProcessed} = 1;
  return $m;
}

__END__
Changes

        - Show if module loads well (eval require)
        - Show if there's a newer version on cpan

2.3.0   2014-11-05
        - Show if XS bindings
        - Show if from RPM system install

2.2.0   2014-11-05
        - Show if module is in core of perl

2.1.0   2014-11-05
        - Performance improvement
        - Show more than 1 path. Good for repairing module library

