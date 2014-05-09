#!/usr/bin/env perl
#
use Modern::Perl;
use version; our $VERSION = qv('v0.1.1');
use 5.010001;

use namespace::autoclean;
use English qw(-no_match_vars); # Avoids regex perf penalty, perl < v5.016000

use Moose;
extends qw(AppState::Ext::Constants);

use AppState;
use File::Path();
use DateTime;
use Software::License;
use PPI;
use File::Find ();
use Module::Metadata;

use Text::Wrap;
$Text::Wrap::columns = 78;

use constant
{ buildbuilder_markfile => '.buildBuilder'
};

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
Name of the distribution. The argument is optional. When used, the distribution
will be generated anew in a directory in the same way h2xs does. The directory
and a minimum number of files are generated. The setup will be all based on the
module Module::Build. In the distribution directory is a YAML file named
Project.yml. The file can be edited after which the program can be used to
update several files in the distribution.
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
        [ [ 'appstate|A'        => 'Use AppState, implicates the use of Moose']
        , [ 'git|G!'            => 'Use Git version control system']
        , [ 'help|h'            => 'Help on this program']
        , [ 'moose|M'           => 'Use Moose in modules']
        , [ 'scrutinize|S'      => 'Run scrutinize program']
        , [ 'verbose|v+'        => 'Show info, errors and warning depending repeats']
        , [ 'version|V=s'       => 'Minimal perl version']
        ]
      }
    , init_arg                  => undef
    , lazy                      => 1
    );

has search_dependency_store =>
    ( is                        => 'rw'
    , isa                       => 'HashRef'
    , default                   => sub { return {}; }
    , traits                    => ['Hash']
    , handles                   =>
      { get_search_dependency           => 'get'
      , set_search_dependency           => 'set'
      , get_search_dependency_keys      => 'keys'
      , clear_search_dependency_store   => 'clear'
      }
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

has test_dependencies =>
    ( is                        => 'rw'
    , isa                       => 'HashRef'
    , default                   => sub { return {}; }
    , traits                    => ['Hash']
    , handles                   =>
      { get_test_dependency     => 'get'
      , set_test_dependency     => 'set'
      , get_test_dep_keys       => 'keys'
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

    $self->const( 'C_DISTRODIREXISTS',  qw(M_ERROR M_FAIL));
    $self->const( 'C_EVALERROR',        qw(M_ERROR M_FAIL));
    $self->const( 'C_MARKFILEFOUND',    qw(M_ERROR M_FAIL));
    $self->const( 'C_MARKFILENOTFOUND', qw(M_ERROR M_FAIL));
    $self->const( 'C_ILLDISTRONAME',    qw(M_ERROR M_FAIL));
    $self->const( 'C_PROJECTREADERR',   qw(M_ERROR M_FAIL));
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
$app->initialize( use_work_dir => 0, use_temp_dir => 0);
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

# Use of AppState implicates use of Moose
#
$cmd->set_option(moose => 1) if $cmd->get_option('appstate');

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

      $self->sayit( "Problems reading project file $f, abort ..."
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

  # Check distro name
  #
  if( $distro_name !~ m/^[\w_:]+$/ )
  {
    $self->sayit( "Illegal ditribution name '$distro_name'"
                , $self->C_ILLDISTRONAME
                );
    return;
  }

  # Prevent builder to build distribution in toplevel distribution directory
  #
  if( -r buildbuilder_markfile )
  {
    $self->sayit( 'Build builder markfile found.', $self->C_MARKFILEFOUND);
    $self->leave;
  }

  my $date = DateTime->now(time_zone => 'Europe/Amsterdam');

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');
  my $log = $app->get_app_object('Log');
  my $cfm = $app->get_app_object('ConfigManager');

  my $perl_version = $cmd->get_option('version') // $PERL_VERSION;
  my $use_moose = $cmd->get_option('moose') // '';
  my $use_appstate = $cmd->get_option('appstate') // '';
  my $use_scrutinize = $cmd->get_option('scrutinize') // '';
  my $use_git = $cmd->get_option('git') // '';

  my $distro_path = $distro_name;
  $distro_path =~ s/::/\//g;
  $distro_path .= '.pm';

  my $distro_dir = $distro_name;
  $distro_dir =~ s/::/-/g;

  my $module_path = "$distro_dir/lib/$distro_path";
  my $module_dir = "lib/$distro_path";
  $module_dir =~ s@/[^/]+$@@;
#  my($module_filename) = $distro_name =~ m/::(;

#say "DN: $distro_name, $distro_path, $distro_dir, $module_path, $module_dir";
#$self->leave;

  if( -d $distro_dir )
  {
    $self->sayit( "Directory for distribution $distro_name exists"
                , $self->C_DISTRODIREXISTS
                );
  }

  else
  {
    $self->sayit( "\nCreating distribution $distro_name", $self->C_INFO);

    # Create directories
    #
#    File::Path::make_path( $distro_dir, {mode => oct(755)});
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

    $cfm->set_documents([{}]);
    $cfm->select_document(0);

    $cfm->set_value( 'Application/name', $distro_name);
    $cfm->set_value( 'Application/abstract'
                   , 'Module to do something interresting'
                   );
    $cfm->set_value( 'Application/author/name', $username);
    $cfm->set_value( 'Application/author/email'
                   , "$username\@some-provider.com"
                   );
    $cfm->set_value( 'Application/copyright', $date->year);
    $cfm->set_value( 'Application/documentation', ['README']);
    $cfm->set_value( 'Application/licenses', ['Perl_5']);
    $cfm->set_value( 'Application/notes', []);
    use version; $cfm->set_value( 'Application/version', qv('0.0.1'));
    $cfm->set_value( 'Application/use_moose', $use_moose);
    $cfm->set_value( 'Application/use_appstate', $use_appstate);
    $cfm->set_value( 'Application/use_scrutinize', $use_scrutinize);
    $cfm->set_value( 'Application/use_git', $use_git);
#    $cfm->set_value( 'Application/dependencies', {});
#    $cfm->set_value( 'Application/install-test', {});
    $cfm->set_value( 'Build/modulebuildrc'
                   , { '*'      => { verbose => 0}
#                     , install  => { install_base => '/home/marcel/Software'}
                     , test     => { verbose => 1}
                     }
                   );

    $cfm->set_value( 'Perl/perl_version', $perl_version);
    $cfm->set_value
          ( 'Perl/critic_rc'
          , { Defaults =>
              { severity                => 3                   
              , only                    => 1                                 
              , force                   => 0                                 
              , verbose                 => 4                                 
              , top                     => 50                                
              , theme                   => '(pbp || security) && bugs'
              , include                 => 'NamingConventions ClassHierarchies'
              , exclude                 => 'Variables  Modules::RequirePackage'
              , 'criticism-fatal'       => 1                           
              , color                   => 1                                 
              , 'allow-unsafe'          => 1                              
              , pager                   => 'less'                             
              }

            , 'Example::TestingAndDebugging::RequireUseStrict' =>
              { equivalent_modules      => 'Modern::Perl'
              , severity                => 1
              , set_themes              => 'foo bar'
              , add_themes              => 'baz'
              , maximum_violations_per_document => 57
              , arg1                    => 'value1'
              , arg2                    => 'value2'
              }

            , 'TestingAndDebugging::RequireUseStrict' =>
              { equivalent_modules => 'Modern::Perl'
              }

            , 'TestingAndDebugging::RequireUseWarnings' =>
              { equivalent_modules => 'Modern::Perl'
              }

            , 'Subroutines::RequireArgUnpacking' =>
              { short_subroutine_statements => 5
              }

            , 'Documentation::PodSpelling' =>
              { stop_words => 'Timmerman'
              }
            }
          );

    $cfm->set_value( 'Bugs', {});
    $cfm->set_value( 'Changes'
                   , [ { date           => $date->ymd
                       , version        => '0.0.1'
                       , module         => $distro_name
                       , program        => 'example_program.pl'
                       , descriptions   =>
                         [ "Original version; created by buildBuilder version $VERSION"
                         , ( $use_appstate
                             ? 'Use AppState modules in program and module'
                             : ( $use_moose
                                 ? 'Use Moose modules in program and modules'
                                 : 'Simple setup in program and modules'
                               )
                           )
                         ]
                       }
                     ]
                   );
    $cfm->set_value( 'Cpan/Account', '');
    $cfm->set_value( 'Git/github/account', '');
    $cfm->set_value( 'Git/github/repository', '');
    $cfm->set_value( 'Git/git-ignore-list'
                   , [ qw( .git ~* *.bak .directory
                           MYMETA* MANIFEST* 
                           blib _build
                           Build Build.bat Build.COM BUILD.COM build.com
                           Distribution-Tests/* Old/* Tests/* *.tgz *.tb2
                           *.tar *.tar.gz *.tar.b2 pm_to_blib
                           script/example_program.pl
                         )
                     ]
                   );
    $cfm->set_value( 'Manifest-skip-list'
                   , [ '^\..*', "\\b$distro_dir" . '-[\d\.\_]+'
                     , qw( ^MYMETA\. \bBuild$ \bBuild.bat$ ~$ \.bak$
                           ^MANIFEST\.SKIP
                           \bblib \b_build
                           \bBuild.COM$ \bBUILD.COM$ \bbuild.com$
                           \bDistribution-Tests/\.* \bProject.yml$
                           \bOld/.* \bTests/.* .*\.tgz$ .*\.tb2$
                           .*\.tar$ .*\.tar\.gz$ .*\.tar\.b2$ \bpm_to_blib$
                           ^script/example_program.pl$
                         )
                     ]
                   );

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
    use $distro_name;
    my \$obj = $distro_name->new();
EOTXT
                   );
    $cfm->set_value( 'Tests'
                   , [ { module => $distro_name
                       , 'test-programs' => [ 't/100-test.t' ]
                       }
                     ]
                   );
    $cfm->set_value( 'Todo', { $date->ymd => 'Think of what to build'});

    $cfm->save;
    $self->sayit( 'Project.yml generated', $self->C_INFO);


    $self->mark_distribution($distro_dir);

    $self->generate_module( $cfm, $distro_name, $module_path);
    $self->generate_program( $cfm, $distro_name, $distro_dir);
    $self->generate_test_program( $cfm, $distro_name, $distro_dir);

    $self->find_dependencies( $distro_name, $distro_dir);
#    $self->find_config_dependencies( $distro_name, $distro_dir);

    $self->generate_readme_and_license( $cfm, $distro_dir);
    $self->generate_changes( $cfm, $distro_dir);

    $self->generate_buildpl( $cfm, $distro_name, $distro_dir, $module_path);
    $self->generate_manifest_skip_list( $cfm, $distro_dir);
    $self->generate_run_buildpl($distro_dir);

    if( $cfm->get_value('Application/use_scrutinize') )
    {
      $self->generate_perlcriticrc($distro_dir);
      $self->run_scrutinize($distro_dir);
    }

    if( $cfm->get_value('Application/use_git') )
    {
      $self->generate_gitignore($distro_dir);
      $self->run_git($distro_dir);
    }
  }

  return;
}

#-------------------------------------------------------------------------------
#
sub updateDistro
{
  my( $self) = @_;

  # Check if this is a builded distribution of this program.
  #
  if( ! -r buildbuilder_markfile )
  {
    $self->sayit( 'Build builder markfile not found.'
                , $self->C_MARKFILENOTFOUND
                );
    $self->leave;
  }

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');
  my $log = $app->get_app_object('Log');
  my $cfm = $app->get_app_object('ConfigManager');

  # Read Project.yml
  #
  $cfm->add_config_object( 'Project'
                         , { store_type       => 'Yaml'
                           , location         => $cfm->C_CFF_FILEPATH
                           , requestFile      => 'Project'
                           }
                         );

  $self->leave unless $self->loadProjectConfig;

  $cfm->select_document(0);

  my $distro_name = $cfm->get_value('Application/name');
  $self->sayit( "\nUpdate $distro_name distribution", $self->C_INFO);

  my $distro_path = $distro_name;
  $distro_path =~ s/::/\//g;
  $distro_path .= '.pm';

  my $distro_dir = '.';
#  $distro_dir =~ s/::/-/g;

  my $module_path = "lib/$distro_path";
#  my $module_dir = "lib/$distro_path";
#  $module_dir =~ s@/[^/]+$@@;

#say "M: $module_path, $distro_path";
#return;

  $self->find_dependencies( $distro_name, $distro_dir);
#  $self->find_config_dependencies( $distro_name, $distro_dir);

  $self->generate_readme_and_license( $cfm, $distro_dir);
  $self->generate_changes( $cfm, $distro_dir);

  $self->generate_buildpl( $cfm, $distro_name, $distro_dir, $module_path);
  $self->generate_manifest_skip_list( $cfm, $distro_dir);
  $self->generate_run_buildpl($distro_dir);

  $self->generate_gitignore($distro_dir)
     if $cfm->get_value('Application/use_git');
  $self->generate_perlcriticrc($distro_dir)
     if $cfm->get_value('Application/use_scrutinize');

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

  $self->wlog( $message, $code);
  say $message if $cmd->get_option('verbose');

  return;
}

#-------------------------------------------------------------------------------
# Generate the distribution module
#
sub generate_module
{
  my( $self, $cfm, $distro_name, $module_path) = @_;

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');

  my $module_version = $cfm->get_value('Application/version');
  my $perl_version = $cfm->get_value('Perl/perl_version');
  my $use_moose = $cfm->get_value('Application/use_moose');
  my $use_appstate = $cfm->get_value('Application/use_appstate');

  my $abstract = $cfm->get_value('Application/abstract');

  #-----------------------------------------------------------------------------
  # Open the module file
  #
  open my $F, '>', "$module_path";

  #-----------------------------------------------------------------------------
  # Write
  #
  print $F <<EOCODE;
package $distro_name;

use Modern::Perl;
use version; our \$VERSION = qv('v$module_version');
use $perl_version;

use namespace::autoclean;
EOCODE

  #-----------------------------------------------------------------------------
  # If AppState option is set, then the module is setup using AppState and Moose
  #
  if( $use_appstate )
  {
    print $F <<EOCODE;
use Moose;
extends qw(AppState::Ext::Constants);

use AppState;

#...

sub BUILD
{
  my(\$self) = \@_;

  if( \$self->meta->is_mutable )
  {
    \$self->code_reset;
#    \$self->const( 'C_SOMECONST0', qw( M_F_INFO M_SUCCESS));
#    \$self->const( 'C_SOMECONST1', qw( M_F_ERROR M_FAIL));
#    \$self->const( 'C_SOMECONST2', qw( M_WARNING M_FORCED));

    __PACKAGE__->meta->make_immutable;
  }
}

#...

# End of package
#
1;

EOCODE
  }

  #-----------------------------------------------------------------------------
  # If Moose option is set, then the module is setup using Moose only
  #
  elsif( $use_moose )
  {
    print $F <<EOCODE;
use Moose;

#...

# End of package
#
__PACKAGE__->meta->make_immutable;
1;

EOCODE
  }

  #-----------------------------------------------------------------------------
  # If no Moose option is set, then the module is setup as a plain class
  #
  else
  {
    print $F <<EOCODE;

# Constructor
#
sub new
{
  my( \$class, \%options) = \@_;

  my \$self = {\%options};

  #...

  return bless \$self, \$class;
}

#...

# End of package
#
1;

EOCODE
  }

  #-----------------------------------------------------------------------------
  # A piece of pod
  #
  print $F "__END__\n\n=head1 NAME\n\n$distro_name - $abstract\n";

  print $F "\n=head1 VERSION\n";
  print $F "\n=head1 SUBROUTINES/METHODS\n";
  print $F "\n=head1 DIAGNOSTICS\n";
  print $F "\n=head1 CONFIGURATION AND ENVIRONMENT\n";
  print $F "\n=head1 DEPENDENCIES\n";
  print $F "\n=head1 INCOMPATIBILITIES\n";
  print $F "\n=head1 BUGS AND LIMITATIONS\n";
  print $F "\n=head1 LICENSE AND COPYRIGHT\n";

  print $F "\n=cut\n";

  #-----------------------------------------------------------------------------
  # Close
  #
  print $F "\n";

  close $F;
  $self->sayit( "$module_path generated", $self->C_INFO);

  return;
}

#-------------------------------------------------------------------------------
# Generate the distribution program
#
sub generate_program
{
  my( $self, $cfm, $distro_name, $distro_dir) = @_;

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');
  
  my $module_version = $cfm->get_value('Application/version');
  my $perl_version = $cfm->get_value('Perl/perl_version');
  my $use_moose = $cfm->get_value('Application/use_moose');
  my $use_appstate = $cfm->get_value('Application/use_appstate');

  #-----------------------------------------------------------------------------
  # Open the module file
  #
  open my $F, '>', "$distro_dir/script/example_program.pl";

  #-----------------------------------------------------------------------------
  # Write
  #
  print $F <<EOCODE;
#!/usr/bin/env perl
#
use Modern::Perl;
use version; our \$VERSION = qv('v$module_version');
use $perl_version;

use $distro_name;

# What I found very usefull is to setup the main as if it where a module so
# it can be instantiated, inherit other modules and so forth.

EOCODE

  #-----------------------------------------------------------------------------
  # If AppState option is set, then the module is setup using AppState and Moose
  #
  if( $use_appstate )
  {
    print $F <<EOCODE;
use Moose;
extends qw(AppState::Ext::Constants);

use AppState;

#...

sub BUILD
{
  my(\$self) = \@_;

  if( \$self->meta->is_mutable )
  {
    \$self->code_reset;
#    \$self->const( 'C_SOMECONST0', qw( M_F_INFO M_SUCCESS));
#    \$self->const( 'C_SOMECONST1', qw( M_F_ERROR M_FAIL));
#    \$self->const( 'C_SOMECONST2', qw( M_WARNING M_FORCED));

    __PACKAGE__->meta->make_immutable;
  }
}

# Make object from the main class
#
my \$self = main->new();

#...

# End of program
#
\$self->leave;

# Destructor
#
sub DEMOLISH
{
  my(\$self) = \@_;

  #...
}

# Subroutines
#
#...

EOCODE
  }

  #-----------------------------------------------------------------------------
  # If Moose option is set, then the module is setup using Moose only
  #
  elsif( $use_moose )
  {
    print $F <<EOCODE;
use Moose;

#...

__PACKAGE__->meta->make_immutable;

# Make object from the main class
#
my \$self = main->new();

#...

# End of program
#
\$self->DESTROY;
exit(0);

# Destructor
#
sub DEMOLISH
{
  my(\$self) = \@_;

  #...
}

# Subroutines
#
#...

EOCODE
  }

  #-----------------------------------------------------------------------------
  # If no Moose option is set, then the module is setup as a plain class
  #
  else
  {
    print $F <<EOCODE;
#...

# Make object from the main class
#
my \$self = main->new();

#...

# End of program
#
\$self->DESTROY;
exit(0);

# Constructor
#
sub new
{
  my( \$class, \%options) = \@_;

  my \$self = {\%options};

  #...

  return bless \$self, \$class;
}

# Destructor
#
sub DESTROY
{
  my(\$self) = \@_;

  #...
}

# Subroutines
#
#...

EOCODE
  }

  #-----------------------------------------------------------------------------
  # Close
  #
  print $F "\n";

  close $F;
  $self->sayit( "$distro_dir/script/program.pl generated", $self->C_INFO);

  return;
}

#-------------------------------------------------------------------------------
# Generate the test program
#
sub generate_test_program
{
  my( $self, $cfm, $distro_name, $distro_dir) = @_;

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');

  my $module_version = $cfm->get_value('Application/version');
  my $perl_version = $cfm->get_value('Perl/perl_version');
  my $use_moose = $cfm->get_value('Application/use_moose');
  my $use_appstate = $cfm->get_value('Application/use_appstate');

  #-----------------------------------------------------------------------------
  # Open the module file
  #
  open my $F, '>', "$distro_dir/t/100-test.t";

  #-----------------------------------------------------------------------------
  # Write
  #
  print $F <<EOCODE;
use Modern::Perl;

use Test::More;

EOCODE

  #-----------------------------------------------------------------------------
  # If AppState option is set, then the module is setup using AppState and Moose
  #
  if( $use_appstate )
  {
    print $F <<EOCODE;
use AppState;
require File::Path;

#-------------------------------------------------------------------------------
# Init
#
my \$app = AppState->instance;
\$app->use_work_dir(0);
\$app->use_temp_dir(0);
\$app->initialize( config_dir => 't/100-Test');
\$app->check_directories;


my \$log = \$app->get_app_object('Log');
#\$log->show_on_error(0);
\$log->show_on_warning(1);
\$log->do_append_log(0);

\$log->start_logging;

\$log->do_flush_log(1);
\$log->log_mask(\$log->M_SEVERITY);

\$log->add_tag('100');

#-------------------------------------------------------------------------------
# Start testing
#
BEGIN { use_ok('$distro_name') };

#...

#-------------------------------------------------------------------------------
# Cleanup and exit
#
done_testing();
\$app->cleanup;

File::Path::remove_tree( 't/100-Test', {verbose => 1});

EOCODE

  }

  #-----------------------------------------------------------------------------
  # Anything else can be tested without wisles and bells
  #
  else
  {
    print $F <<EOCODE;
#-------------------------------------------------------------------------------
# Start testing
#
BEGIN { use_ok('$distro_name') };

#-------------------------------------------------------------------------------
# Cleanup and exit
#
done_testing();
EOCODE
  }

  #-----------------------------------------------------------------------------
  # Close
  #
  print $F "\n";

  close $F;
  $self->sayit( "$distro_dir/t/100-test.t generated", $self->C_INFO);

  return;
}

#-------------------------------------------------------------------------------
#
sub find_dependencies
{
  my( $self, $distro_name, $distro_dir) = @_;

  my $dep_data = { dependencies => [ "$distro_dir/lib", "$distro_dir/script"]
                 , test_dependencies => [ "$distro_dir/t"]
                 };

  foreach my $dependencies (keys %$dep_data)
  {
    # Clear the search store
    #
    $self->clear_search_dependency_store;

    # Search in each .pl or .pm file for use or require statements. Look in
    # the directories under lib and under script.
    # Collect the module names and find the versions of them.
    #
    File::Find::find
    ( { wanted => sub { $self->search_through_files( $distro_name
                                                   , $distro_dir
                                                   , @_
                                                   );
                      }
      }
    , @{$dep_data->{$dependencies}}
    );

    # Get results from the search store and put them in the dependencies hash
    #
    $self->$dependencies($self->search_dependency_store);
  }

  return;
}

#-------------------------------------------------------------------------------
#
sub search_through_files
{
  my( $self, $distro_name, $distro_dir) = @_;
  my $dir = $File::Find::dir;
  my $file = $_;

  return if -d $file;
  return if "$dir/$file" =~ m/\.git\//;
  return unless $file =~ m/.*?\.(t|pl|PL|pm)$/s;

  my $ppi_doc = PPI::Document->new($file);
  my $incl_nodes = $ppi_doc->find
              ( sub { $_[1]->isa('PPI::Statement::Include') }
              );
  foreach my $node (@$incl_nodes)
  {
    my $type = $node->type // '';
    my $module = $node->module // '';
    my $module_version = $node->module_version // '0';

    if( $module and !$module_version )
    {
#say "Search in: $module";
      my $meta = Module::Metadata->new_from_module($module);
      $module_version = $meta->version if defined $meta;
    }

    # Only add/modify when not defined or has zero version
    #
    my $mod_dep = $self->get_search_dependency ($module);
    if( $type =~ m/^use|require$/ and $module
        and $module !~ m/^$distro_name\b/
        and ( !defined $mod_dep or !$mod_dep )
      )
    {
      $self->set_search_dependency( $module => $module_version);
    }
  }
}

#-------------------------------------------------------------------------------
#
sub generate_readme_and_license
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
  # Open the readme file
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
  foreach my $dep (sort $self->get_dep_keys)
  {
    say $F sprintf( "    %-40s %-10s", $dep, $self->get_dependency($dep));
  }

  say $F "\n  Installation and testing";
  foreach my $dep (sort $self->get_test_dep_keys)
  {
    say $F sprintf( "    %-40s %-10s", $dep, $self->get_test_dependency($dep));
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
    say $F "See also file LICENSE_$license\n";
  }

  #-----------------------------------------------------------------------------
  # Close
  #
  say $F "\n";

  close $F;
  $self->sayit( 'README generated', $self->C_INFO);



  #-----------------------------------------------------------------------------
  # Generate license files with full text
  #
  foreach my $license (@{$cfm->get_value('Application/licenses')})
  {
    # Skip if the file is already generated. The content should never change.
    #
    next if -r "$distro_dir/LICENSE_$license";

    open my $F, '>', "$distro_dir/LICENSE_$license";

    my $license_obj;
    my $code = <<EOCODE;
require Software::License::$license;
\$license_obj = Software::License::$license->new ({holder => \$author});
EOCODE

    eval($code);
    my $error = $@;
    if( $error )
    {
      $self->sayit( "Error evaluating code: $error", $self->C_EVALERROR);
      $self->leave;
    }

    say $F $license_obj->fulltext;

    close $F;
    $self->sayit( "LICENSE_$license generated", $self->C_INFO);
  }

  return;
}

#-------------------------------------------------------------------------------
#
sub generate_changes
{
  my( $self, $cfm, $distro_dir) = @_;

  my $app = AppState->instance;
  my $log = $app->get_app_object('Log');

  #-----------------------------------------------------------------------------
  # Open the readme file
  #
  open my $F, '>', "$distro_dir/Changes";

  #-----------------------------------------------------------------------------
  # Write changes
  #
  foreach my $change (@{$cfm->get_value('Changes')})
  {
    my $module = $change->{module} // '';
    my $program = " $change->{program}" // '';

    print $F sprintf( "\n%-9s %-12s %s%s\n"
                    , $change->{version}, $change->{date}, $module, $program
                    );
    say $F Text::Wrap::wrap( "        - ", "            "
                           , $change->{description}
                           ) if defined $change->{description};
    foreach my $description (@{$change->{descriptions}})
    {
      say $F Text::Wrap::wrap( "        - ", "            ", $description);
    }
  }

  #-----------------------------------------------------------------------------
  # Close
  #
  say $F "\n";

  close $F;
  $self->sayit( 'Changes generated', $self->C_INFO);

  return;
}

#-------------------------------------------------------------------------------
#
sub generate_buildpl
{
  my( $self, $cfm, $distro_name, $distro_dir, $module_path) = @_;

  my $app = AppState->instance;
#  my $cmd = $app->get_app_object('CommandLine');
  my $log = $app->get_app_object('Log');

  #-----------------------------------------------------------------------------
  # Open the readme file
  #
  open my $F, '>', "$distro_dir/Build.PL";

  #-----------------------------------------------------------------------------
  # Write Build.PL
  #
  my $author = $cfm->get_value('Application/author/name');
  my $email = $cfm->get_value('Application/author/email');
  my $abstract = $cfm->get_value('/Application/abstract');
  my $license = $cfm->get_value('/Application/licenses')->[0];

#  my $verbose = $cmd->get_option('verbose') ? '1' : '0';
#  my $quiet = $cmd->get_option('quiet') ? '1' : '0';

  my $mp = $module_path;
  $mp =~ s@^[^/]+/@@;

  print $F <<EOCODE;
#!/usr/bin/perl
#
require Modern::Perl;
require Module::Build;
#require Module::Build::ConfigData;

my \$build = Module::Build->new
( module_name           => '$distro_name'
, dist_name             => '$distro_dir'
, abstract              => '$abstract'
, author                => '$author <$email>'

, license               => '$license'
, create_licence        => 0            # License is generated independently

, release_status        => 'stable'

, tap_harness_args      => { timer => 1
#                           , verbosity => 1
                           , failures => 1
                           , show_count => 1
                           }
, extra_manify_args     => { utf8 => 1 }
, script_files          => 'script'

EOCODE

  # Requirements of the modules
  #
  if( $self->get_dep_keys )
  {
    print $F "\n, requires =>\n  { ";
    my $str_list =
       join( "\n  , "
           , map
             { sprintf( "%-43s => %s"
                      , "'$_'"
                      , "'" . $self->get_dependency($_) . "'"
                      )
             }
             (sort $self->get_dep_keys)
           );
    say $F $str_list, "\n  }\n";
  }

  # Requirements of the installation and testing
  #
  if( $self->get_test_dep_keys )
  {
    print $F ", test_requires =>\n  { ";
    my $str_list =
       join( "\n  , "
           , map
             { sprintf( "%-43s => %s"
                      , "'$_'"
                      , "'" . $self->get_test_dependency($_) . "'"
                      )
             }
             (sort $self->get_test_dep_keys)
           );
    say $F $str_list, "\n  }";
  }

  print $F ");\n\n\$build->create_build_script();\n";

  #-----------------------------------------------------------------------------
  # Close
  #
  say $F "\n";

  close $F;
  $self->sayit( 'Build.PL generated', $self->C_INFO);

  return;
}

#-------------------------------------------------------------------------------
#
sub generate_manifest_skip_list
{
  my( $self, $cfm, $distro_dir) = @_;

  my $app = AppState->instance;
  my $log = $app->get_app_object('Log');

  #-----------------------------------------------------------------------------
  # Open the manifest skip list file
  #
  open my $F, '>', "$distro_dir/MANIFEST.SKIP";

  my $skip_list = $cfm->get_value('Manifest-skip-list');
  foreach my $skip (sort @$skip_list)
  {
    say $F $skip;
  }

  #-----------------------------------------------------------------------------
  #
  close $F;
  $self->sayit( 'MANIFEST.SKIP generated', $self->C_INFO);

  return;
}

#-------------------------------------------------------------------------------
#
sub generate_run_buildpl
{
  my( $self, $distro_dir) = @_;

  chdir($distro_dir) unless $distro_dir eq '.';

  my $app = AppState->instance;
  my $cfm = $app->get_app_object('ConfigManager');

  my $show_program;
  open my $MBRC, '>', '.modulebuildrc';
  foreach my $program (@{$cfm->get_keys('Build/modulebuildrc')})
  {
    $show_program = 1;
    foreach my $argument (@{$cfm->get_keys("Build/modulebuildrc/$program")})
    {
      my $value = $cfm->get_value("Build/modulebuildrc/$program/$argument");
      say $MBRC sprintf( "%-18s --%s %s"
                       , $show_program ? $program : ''
                       , $argument
                       , $value
                       );

      $show_program = 0;
    }
  }

  close $MBRC;
  $self->sayit( '.modulebuildrc written', $self->C_INFO);
  $ENV{'MODULEBUILDRC'} = '.modulebuildrc';
  $self->sayit( '$ENV{MODULEBUILDRC} set', $self->C_INFO);


  # Fake a manifest file after which it will be generated when Build exists
  #
  system('/usr/bin/echo Build.PL >MANIFEST') unless -r 'MANIFEST';

  # Generate the Build program
  #
  system('/usr/bin/env perl Build.PL');
  $self->sayit( 'Build.PL executed', $self->C_INFO);

  # Generate the real MANIFEST
  #
  system('./Build manifest');
  $self->sayit( 'Build manifest executed', $self->C_INFO);

  # Make the distribution
  #
  system('./Build');
  $self->sayit( 'Build executed', $self->C_INFO);

  # Test the distribution
  #
  system('./Build test');
  $self->sayit( 'Build test executed', $self->C_INFO);

  chdir('..') unless $distro_dir eq '.';
  return;
}

#-------------------------------------------------------------------------------
#
sub generate_perlcriticrc
{
  my( $self, $distro_dir) = @_;

  open my $PCRC, '>', "$distro_dir/.perlcriticrc";

  my $defaults = $cfm->get_keys("Perl/critic_rc/Defaults");
  if( ref $defaults eq 'ARRAY' )
  {
    say $PCRC '#' x 80, "\n", "# Default settings for Perl::Critic";
    foreach my $default (@$defaults)
    {
      say $PCRC "$default = "
        , $cfm->get_value("Perl/critic_rc/Defaults/$default");
    }

    say $PCRC '';
  }

  my $pcrc_keys = $cfm->get_keys('Perl/critic_rc');
  foreach my $block_spec (@$pcrc_keys)
  {
    next if $block_spec eq 'Defaults';

    my $specs = $cfm->get_keys("Perl/critic_rc/$block_spec");
    next unless ref $specs eq 'ARRAY';
    say $PCRC '#' x 80, "\n", "[$block_spec]";
    
    foreach my $spec (@$specs)
    {
      say $PCRC "$spec = "
        , $cfm->get_value("Perl/critic_rc/$block_spec/$spec");
    }

    say $PCRC '';
  }

  close $PCRC;
  $self->sayit( '.perlcriticrc generated', $self->C_INFO);

  return;
}

#-------------------------------------------------------------------------------
#
sub run_scrutinize
{
  my( $self, $distro_dir) = @_;

  chdir($distro_dir) unless $distro_dir eq '.';
#say "Run scrutinize in [$distro_dir] ->", `pwd`;
#$self->leave;

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');
  my $verbose = $cmd->get_option('verbose') ? '-v' : '-q';
  
  system("scrutinize $verbose --prove -l");
  system("scrutinize $verbose --critic");
  system("scrutinize $verbose --metric -l");

  chdir('..') unless $distro_dir eq '.';
  return;
}

#-------------------------------------------------------------------------------
#
sub mark_distribution
{
  my( $self, $distro_dir) = @_;

  my $dt = DateTime->now(time_zone => 'Europe/Amsterdam');
  my $date = $dt->ymd;
  my $time = $dt->hms;

  open my $GI, '>', "$distro_dir/" . buildbuilder_markfile;
  say $GI "Distribution build by buildBuilder at $date $time";
  close $GI;

  return;
}

#-------------------------------------------------------------------------------
#
sub generate_gitignore
{
  my( $self, $distro_dir) = @_;

  open my $GI, '>', "$distro_dir/.gitignore";
  my $gi_list = $cfm->get_value('Git/git-ignore-list');
  say $GI $_ foreach (@$gi_list);
  close $GI;

  return;
}

#-------------------------------------------------------------------------------
#
sub run_git
{
  my( $self, $distro_dir) = @_;

  chdir($distro_dir) unless $distro_dir eq '.';

  # If directory .git does not exist then a new git must be generated
  #
  my $new_git = -d '.git' ? 0 : 1;
  if( $new_git )
  {
    system('/usr/bin/git init');
    system('/usr/bin/git add .');
    system('/usr/bin/git commit -m "Initial commit of distribution"');
    system('/usr/bin/git status');
  }

  chdir('..') unless $distro_dir eq '.';
  return;
}


