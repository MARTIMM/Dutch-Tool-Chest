#!/usr/bin/env perl
#
use Modern::Perl;
use namespace::autoclean;
use English qw(-no_match_vars); # Avoids regex perf penalty, perl < v5.016000

use Moose;
extends qw(AppState::Ext::Constants);

use AppState;
use File::Path();

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
    , init_arg          => undef
    , lazy              => 1
    );

has options =>
    ( is                => 'ro'
    , isa               => 'ArrayRef'
    , default           =>
      sub
      { return
        [ [ 'help|h'    => 'Help on this program']
        , [ 'verbose|v' => 'Show all tests done by prove']
        ]
      }
    , init_arg          => undef
    , lazy              => 1
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
#    $self->const( '',qw(M_ERROR M_FAIL));
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

my $app = AppState->instance;
$app->initialize;
$app->check_directories;

#-------------------------------------------------------------------------------
# Setup logging
#
my $log = $app->get_app_object('Log');
$log->log_file('Distribution-Tests.log');

#$log->show_on_error(0);
$log->do_append_log(0);

$log->start_logging;

#$log->do_flush_log(1);
#  $log->log_mask($self->M_ERROR|$self->M_WARNING);
$log->log_mask($self->M_ERROR|$self->M_WARNING|$self->M_INFO);

$log->add_tag('.BB');

#-------------------------------------------------------------------------------
# Setup command description and check help option.
#
my $cmd = $app->get_app_object('CommandLine');
$cmd->config_getopt_long(qw(bundling));

# Defaults
#
$cmd->setOption( blib => 0, lib => 0, verbose => 1);

# Initialize
#
$cmd->initialize( $self->description, $self->arguments, $self->options
#m              , $self->usage, $self->examples
                );
#say (join ', ', map {"$_=" . $cmd->getOption($_)} sort $cmd->get_options);

# Noverbose or quiet will make proving less noisy
#
$cmd->setOption(verbose => 0) if $cmd->getOption('quiet');

if( $log->get_last_error == $cmd->C_CMD_OPTPROCFAIL or $cmd->getOption('help'))
{
  say $cmd->usage;
  $self->leave;
}

#-------------------------------------------------------------------------------
# Setup application config file
#
my $cfm = $app->get_app_object('ConfigManager');
$cfm->select_config_object('defaultConfigObject');
$cfm->load;
$cfm->set_documents([]) unless $cfm->nbr_documents;
#$log->show_on_warning(1);

#-------------------------------------------------------------------------------
#
my @args = $cmd->get_arguments;
if( @args )
{
  $self->sayit( "Creating new distribution environments", $self->C_INFO);

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

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');
  my $log = $app->get_app_object('Log');
  my $cfm = $app->get_app_object('ConfigManager');

  if( -d $distro_name )
  {
    $self->_log( "Directory $distro_name exists", $self->C_DISTRODIREXISTS);
  }

  else
  {
    # Create directories
    #
    File::Path::make_path( $distro_name, {mode => oct(760)});
    chdir($distro_name);

    File::Path::make_path( 'lib', "lib/$distro_name", 't', 'script', 'doc'
                         , {mode => oct(760)}
                         );

    $self->sayit( "Directories created", $self->C_DIRSCREATED);


    $cfm->add_config_object( 'Project'
                           , { store_type       => 'Yaml'
                             , location         => $cfm->C_CFF_FILEPATH
                             , requestFile      => 'Project'
                             }
                           );

    $self->leave unless $self->loadProjectConfig;
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
  say "Update $distro_name distribution";

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








