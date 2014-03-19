#!/usr/bin/env perl
#
use Modern::Perl;
use version; our $VERSION = qv('v0.0.1');
use 5.010001;

use namespace::autoclean;
use English qw(-no_match_vars); # Avoids regex perf penalty, perl < v5.016000

use Moose;
extends qw(AppState::Ext::Constants);

use AppState;
use File::Path();
use DateTime;
use Software::License;

#-------------------------------------------------------------------------------
#
has description =>
    ( is                => 'ro'
    , isa               => 'Str'
    , default           => <<EODSCR
Program to create a standard Perl distribution based on information from a file
Project.yml in the current directory. The required files and directories are
created and or updated with the information found in Project.yml'. The
distribution will then use Module::Build. The file Build.PL among others is
generated or rewritten.
EODSCR
    , init_arg          => undef
    , lazy              => 1
    );

has arguments =>
    ( is                => 'ro'
    , isa               => 'ArrayRef'
    , default           =>
      sub
      { return
        [ [ 'distribution-name' => <<EODSCR
Optional a name can be given when nothing has been generated. The directory and
a minimum number of files are generated. After that phase in the directory the
Project.yml file can be used to add information and change a few of the
distribution files.
EODSCR
          ]
        ]
      }
    , init_arg                  => undef
    , lazy                      => 1
    );

has options =>
    ( is                        => 'ro'
    , isa                       => 'ArrayRef'
    , default                   =>
      sub
      { return
        [ [ 'help|h'            => 'Help on this program']
        , [ 'verbose|v+'        => 'Show all tests done by prove']
        ]
      }
    , init_arg                  => undef
    , lazy                      => 1
    );

has dependencies =>
    ( is                        => 'rw'
    , isa                       => 'HashRef'
    , default                   => sub { return {}; }
    , traits                    => ['Hash']
    , handles                   =>
      { get_dependency          => 'get'
      , set_dependency          => 'set'
      , get_dep_keys            => 'keys'
      }
    );

has config_dependencies =>
    ( is                        => 'rw'
    , isa                       => 'HashRef'
    , default                   => sub { return {}; }
    , traits                    => ['Hash']
    , handles                   =>
      { get_conf_dependency     => 'get'
      , set_conf_dependency     => 'set'
      , get_conf_dep_keys       => 'keys'
      }
    );

#-------------------------------------------------------------------------------
#
sub BUILD
{
  my($self) = @_;

  if( $self->meta->is_mutable )
  {
    # Error codes
    #
    $self->code_reset;
    $self->const( 'C_INFO',             qw(M_INFO M_SUCCESS));
    $self->const( 'C_DIRSCREATED',      qw(M_INFO M_SUCCESS));
#    $self->const( '',qw(M_INFO M_SUCCESS));
#    $self->const( '',qw(M_INFO M_SUCCESS));
#    $self->const( '',qw(M_INFO M_SUCCESS));

    $self->const( 'C_DISTRODIREXISTS',  qw(M_ERROR M_FORCED));
    $self->const( 'C_EVALERROR',        qw(M_ERROR M_FAIL));
#    $self->const( '',qw(M_ERROR M_FAIL));
#    $self->const( '',qw(M_ERROR M_FAIL));
#    $self->const( '',qw(M_ERROR M_FAIL));

    $self->meta->make_immutable;
  }
}

#-------------------------------------------------------------------------------
# Create Main object
#
my $self = main->new;

#-------------------------------------------------------------------------------
# Get AppState object. Plan is not to use a temp and work directory.
#
my $app = AppState->instance;
$app->use_work_dir(0);
$app->use_temp_dir(0);
$app->initialize;
$app->check_directories;

#-------------------------------------------------------------------------------
# Setup logging
#
my $log = $app->get_app_object('Log');

$log->show_on_error(0);
$log->show_on_warning(0);
$log->do_append_log(0);

$log->start_logging;

#$log->do_flush_log(1);
$log->log_mask($self->M_SEVERITY);

$log->add_tag('.BB');

#-------------------------------------------------------------------------------
# Setup command description and check help option.
#
my $cmd = $app->get_app_object('CommandLine');
$cmd->config_getopt_long(qw(bundling));

# Defaults
#
$cmd->set_option( verbose => 0);

# Initialize
#
$cmd->initialize( $self->description, $self->arguments, $self->options
#               , $self->usage, $self->examples
                );
#say (join ', ', map {"$_=" . $cmd->getOption($_)} sort $cmd->get_options);

# Noverbose or quiet will make proving less noisy
#
#$cmd->set_option(verbose => 0) if $cmd->getOption('quiet');

if( $log->get_last_error == $cmd->C_CMD_OPTPROCFAIL or $cmd->get_option('help'))
{
  say $cmd->usage;
  $self->leave;
}

$log->show_on_error(1) if $cmd->get_option('verbose') > 1;
$log->show_on_warning(1) if $cmd->get_option('verbose') > 2;

#-------------------------------------------------------------------------------
# Setup application config file
#
my $cfm = $app->get_app_object('ConfigManager');
$cfm->select_config_object('defaultConfigObject');
$cfm->requestFile('buildBuilder');
$cfm->load;
if( $cfm->nbr_documents == 0 )
{
  $cfm->set_documents([{}]);
  $cfm->save;
}

#-------------------------------------------------------------------------------
#
my @args = $cmd->get_arguments;
if( @args )
{
  $self->sayit( "\nCreating new distribution environments", $self->C_INFO);

  foreach my $distro_name (@args)
  {
    $self->createNewDistro($distro_name);
  }
}

else
{
  $self->updateDistro;
}

#-------------------------------------------------------------------------------
$self->leave;
exit(0);



#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
#
sub loadProjectConfig
{
  my( $self) = @_;
  my $app = AppState->instance;
  my $log = $app->get_app_object('Log');
  my $cfm = $app->get_app_object('ConfigManager');

  my $sts = 0;
  $cfm->select_config_object('Project');
  if( $log->get_last_error == $cfm->C_CFM_CFGSELECTED )
  {
    $cfm->load;
    if( $log->get_last_error == $cfm->C_CIO_DESERIALFAIL )
    {
      my $f = $cfm->configFile;
      $f =~ s@.*?([^/]+)$@$1@;

      $self->_log( "Problems reading project file $f, abort ..."
                 , $self->C_PROJECTREADERR
                 );
    }

    else
    {
      $sts = 1;
    }
  }

  return $sts;
}

#-------------------------------------------------------------------------------
#
sub createNewDistro
{
  my( $self, $distro_name) = @_;

  $self->sayit( "Creating distribution $distro_name", $self->C_INFO);

  my $date = DateTime->now(time_zone => 'Europe/Amsterdam');

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');
  my $log = $app->get_app_object('Log');
  my $cfm = $app->get_app_object('ConfigManager');
  
  my $distro_path = $distro_name;
  $distro_path =~ s/::/\//g;
  $distro_path .= '.pm';

  my $distro_dir = $distro_name;
  $distro_dir =~ s/::/-/g;

  my $module_path = "$distro_dir/lib/$distro_path";
  my $module_dir = "lib/$distro_path";
  $module_dir =~ s@/[^/]+$@@;
#  my($module_filename) = $distro_name =~ m/::(;
  
say "DN: $distro_name, $distro_path, $distro_dir, $module_path, $module_dir";
#$self->leave;

  if( -d $distro_dir )
  {
    $self->_log( "Directory $distro_name exists", $self->C_DISTRODIREXISTS);
  }

  else
  {
    # Create directories
    #
    File::Path::make_path( $distro_dir, {mode => oct(755)});
#    chdir($distro_name);

    File::Path::make_path( "$distro_dir/lib", "$distro_dir/$module_dir"
                         , "$distro_dir/t", "$distro_dir/script"
                         , "$distro_dir/doc"
                         , {mode => oct(755)}
                         );

    $self->sayit( "Directories created", $self->C_DIRSCREATED);

    # Create Project.yml
    #
    $cfm->add_config_object( 'Project'
                           , { store_type       => 'Yaml'
                             , location         => $cfm->C_CFF_FILEPATH
                             , requestFile      => "$distro_dir/Project"
                             }
                           );

    my $username = getpwuid $REAL_USER_ID;
    my $dateExample = $date->year . ' ' . $date->month . ' ' . $date->day;

    $cfm->set_documents([{}]);
    $cfm->select_document(0);

    $cfm->set_value( 'Application/name', $distro_name);
    $cfm->set_value( 'Application/abstract', '');
    $cfm->set_value( 'Application/author/name', $username);
    $cfm->set_value( 'Application/author/email', '');
    $cfm->set_value( 'Application/copyright', $date->year);
    $cfm->set_value( 'Application/documentation', ['README']);
    $cfm->set_value( 'Application/licenses', ['Perl_5']);
    $cfm->set_value( 'Application/notes', []);
    $cfm->set_value( 'Application/version', '0.0.1');

    $cfm->set_value( 'Bugs', {});
    $cfm->set_value( 'Changes'
                   , { $dateExample => <<EOTXT
Original version; created by buildBuilder version $VERSION
EOTXT
                     }
                   );
    $cfm->set_value( 'Cpan/Account', '');
    $cfm->set_value( 'Git/github/account', '');
    $cfm->set_value( 'Git/github/repository', '');
    $cfm->set_value( 'Git/github/git-ignore-list', ["'.*'"]);
    $cfm->set_value( 'Manifest-skip-list'
                   , [ "'.*'"
                     , qw( ^_build ^Build$ ^blib ~$ \.bak$ ^MANIFEST\.SKIP$)
                     ]
                   );
#    $cfm->set_value( 'Manifest'
#                   , [ qw( README Changes MANIFEST Build.PL t Doc)
#                     , 'lib/$distro_name'
#                     ]
#                   );
    $cfm->set_value( 'Readme/description', <<EOTXT
    The README is used to introduce the module and provide instructions on how
    to install the module, any machine dependencies it may have (for example C
    compilers and installed libraries) and any other information that should be
    provided before the module is installed.

    A README file is required for CPAN modules since CPAN extracts the README
    file from a module distribution so that people browsing the archive can use
    it get an idea of the modules uses. It is usually a good idea to provide
    version information here so that people can decide whether fixes for the
    module are worth downloading.
EOTXT
                   );
    $cfm->set_value( 'Readme/example', <<EOTXT
    $distro_name [<options>] [<arguments>]
EOTXT
                   );
    $cfm->set_value( 'Tests', {});
    $cfm->set_value( 'Todo', { $dateExample => 'Think of what to build'});

    $cfm->save;
    $self->sayit( 'Project.yml generated', $self->C_INFO);

    $self->find_dependencies;
    $self->find_config_dependencies;

    $self->generate_readme( $cfm, $distro_dir);
#    $self->generate_changes($cfm);
#    $self->generate_manifest($cfm);
#    $self->generate_module($cfm);
#    $self->generate_program($cfm);
#    $self->generate_buildpl($cfm);
  }

  return;
}

#-------------------------------------------------------------------------------
#
sub updateDistro
{
  my( $self) = @_;

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');
  my $log = $app->get_app_object('Log');
  my $cfm = $app->get_app_object('ConfigManager');

  my $distro_name = '';
  $self->sayit( "\nUpdate $distro_name distribution", $self->C_INFO);

  # Read Project.yml
  #
  $cfm->add_config_object( 'Project'
                         , { store_type       => 'Yaml'
                           , location         => $cfm->C_CFF_FILEPATH
                           , requestFile      => 'Project'
                           }
                         );

  $self->leave unless $self->loadProjectConfig;

  return;
}

#-------------------------------------------------------------------------------
#
sub sayit
{
  my( $self, $message, $code) = @_;

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');
  my $log = $app->get_app_object('Log');

  $self->_log( $message, $code);
  say $message if $cmd->get_option('verbose');

  return;
}

#-------------------------------------------------------------------------------
#
sub find_dependencies
{
  my( $self) = @_;

  $self->set_dependency( 'AppState' => '0.4.15');

  return;
}

#-------------------------------------------------------------------------------
#
sub find_config_dependencies
{
  my( $self) = @_;

  $self->set_conf_dependency( 'Module::Build' => '0.4205');
  $self->set_conf_dependency( 'Test::More' => '0.98');
  $self->set_conf_dependency( 'Test::Most' => '0.33');

  return;
}

#-------------------------------------------------------------------------------
#
sub generate_readme
{
  my( $self, $cfm, $distro_dir) = @_;

  my $app = AppState->instance;
  my $log = $app->get_app_object('Log');

  my $author = $cfm->get_value('Application/author/name');
  my $distro_name = $cfm->get_value('Application/name');
  my $version = $cfm->get_value('Application/version');
  my $description = $cfm->get_value('Readme/description');
  my $example = $cfm->get_value('Readme/example');

  #-----------------------------------------------------------------------------
  # Open the redme file
  #
  open my $F, '>', "$distro_dir/README";

  my $first_line = "$distro_name version $version";
  
  #-----------------------------------------------------------------------------
  # Write the top line about the module and version
  #
  say $F $first_line;
  say $F '=' x length($first_line);
  
  #-----------------------------------------------------------------------------
  # Write the introduction and body
  #
  say $F <<EOTXT;

DESCRIPTION

$description

EXAMPLE

$example

EOTXT

  #-----------------------------------------------------------------------------
  # Write the dependencies
  #
  say $F "DEPENDENCIES\n\n  Program and Modules";
  my($perlv) = $PERL_VERSION =~ m/^.(.*)$/;
  say $F sprintf( "    %-40s %-10s", 'perl', $perlv);
  foreach my $dep ($self->get_dep_keys)
  {
    say $F sprintf( "    %-40s %-10s", $dep, $self->get_dependency($dep));
  }

  say $F "\n  Installation and testing";
  foreach my $dep ($self->get_conf_dep_keys)
  {
    say $F sprintf( "    %-40s %-10s", $dep, $self->get_conf_dependency($dep));
  }

  #-----------------------------------------------------------------------------
  # Write the installation method
  #
  say $F <<EOTXT;

INSTALLATION

To install this module type the following:

        perl Build.PL
        Build
        Build test
        Build install

EOTXT

  #-----------------------------------------------------------------------------
  # Write the copyright and license
  #
  say $F "COPYRIGHT AND LICENCE\n\n";

  foreach my $license (@{$cfm->get_value('Application/licenses')})
  {
    my $license_obj;
    my $code = <<EOCODE;
require Software::License::$license;
\$license_obj = Software::License::$license->new
                ( { holder => \$author
                  }
                );
EOCODE

    eval($code);
    my $error = $@;
    if( $error )
    {
      $self->sayit( "Error evaluating code: $error", $self->C_EVALERROR);
      $self->leave;
    }

    say $F $license_obj->notice;
    say $F $license_obj->url // '';
  }

  #-----------------------------------------------------------------------------
  # Close
  #
  say $F "\n";

  close $F;
  $self->sayit( 'README generated', $self->C_INFO);

  return;
}








