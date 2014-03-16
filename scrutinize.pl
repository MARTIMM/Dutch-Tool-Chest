#!/usr/bin/env perl
#
use Modern::Perl;
use namespace::autoclean;
use English qw(-no_match_vars); # Avoids regex perf penalty, perl < v5.016000

use Moose;
extends qw(AppState::Ext::Constants);

use AppState;
use App::Prove;
use Perl::Critic;
use Perl::Critic::Utils::McCabe;
use Perl::MinimumVersion;
use Text::Wrap ('$columns');
$columns = 80;

#-------------------------------------------------------------------------------
#
has description =>
    ( is		=> 'ro'
    , isa		=> 'Str'
    , default		=> <<EODSCR
Program to test a distribution and or get metrics or critics using controlling
information from 'Project.yml' in the current directory. The results of the
tests is stored in a configuration directory 'Distribution-Tests' also in the
current directory. The default will be gathering critics about a module.
EODSCR
    , init_arg		=> undef
    , lazy		=> 1
    );

has usage =>
    ( is		=> 'ro'
    , isa		=> 'ArrayRef'
    , default		=> 
      sub
      { return
	[ "$0 --prove -lbvq <module>            Test modules using App::Prove"
	, "$0 --prove -s <module>               Show prove test results"
	, "$0 --critic <severity> <module>      Test modules using Perl::Critic"
	, "$0 --critic <severity> -ds <module>  Show gathered critics"
	];
      }
    , init_arg		=> undef
    , lazy		=> 1
    );

has arguments =>
    ( is		=> 'ro'
    , isa		=> 'ArrayRef'
    , default		=> 
      sub
      { return
	[ [ 'test-selection'	=> <<EODSCR
One or more words which are used to select the tests from 'Project.yml'. When
no words are given, all tests are executed.
EODSCR
	  ]
	]
      }
    , init_arg		=> undef
    , lazy		=> 1
    );

has options =>
    ( is		=> 'ro'
    , isa		=> 'ArrayRef'
    , default		=> 
      sub
      { return
	[ [ 'blib|b'	=> 'Use library path ./blib, default off.']
	, [ 'critic:s'	=> <<EOTXT
Test programs using critic. Level of critic is given
by a number from 1 to 5 meaning brutal, cruel, harsh, stern or gentle. Default
is 1 or brutal.
EOTXT
          ]
	, [ 'describe|d=s@' => <<EOTXT
Describe selected critic numbers more fully. This option is used with --critic
and --show to show the gathered critisizm upon a module. The critics are
numbered in the first column of the list. When this option is used with the 
selected numbers, more information is shown.
EOTXT
	  ]
	, [ 'help|h'	=> 'Help on this program']
	, [ 'lib|l'	=> 'Use library path ./lib, default off']
        , [ 'metric|m'  => <<EOTXT
Get metrics about modules. Some of the metrics are gathered by other options
like --critic
EOTXT
          ]
	, [ 'prove'	=> 'Test programs using App::prove']
	, [ 'quiet|q'	=> 'Hide test information, default off']
	, [ 'show|s'	=> <<EOTXT
Show results. Use this option in combination with --critic, --metric or --prove.
Tests are not done when this option is used.
EOTXT
	  ]
	, [ 'verbose|v!'=> 'Show all tests done by prove, default on']
	]
      }
    , init_arg		=> undef
    , lazy		=> 1
    );

has examples =>
    ( is		=> 'ro'
    , isa		=> 'ArrayRef'
    , default		=> 
      sub
      { return
	[ [ "$0 --critic=gentle" => <<EOTXT
Run Perl::Critic on modules defined in Project.yml. The severity level is
set to 5 which means 'gentle'.
EOTXT
          ]
	];
      }
    , init_arg		=> undef
    , lazy		=> 1
    );

has _cnvSeverityHash =>
    ( is                => 'ro'
    , isa               => 'HashRef'
    , default           =>
      sub
      {
        return
        { brutal        => 1
        , cruel         => 2
        , harsh         => 3
        , stern         => 4
        , gentle        => 5
        };
      }
    , init_arg          => undef
    , traits            => ['Hash']
    , handles           =>
      { cnvSeverityCode => 'get'
      }
    );
    
has _program_tested =>
    ( is                => 'ro'
    , isa               => 'HashRef'
    , default           => sub { return {}; }
    , init_arg          => undef
    , traits            => ['Hash']
    , handles           =>
      { get_tested_program      => 'get'
      , set_tested_program      => 'set'
      , program_tested          => 'exists'
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
    $self->const( 'C_PROJECTREADERR',   qw(M_ERROR M_FAIL));
    $self->const( 'C_TESTFILENTFND',    qw(M_WARNING));

    $self->meta->make_immutable;
  }

  #-----------------------------------------------------------------------------
  # Setup application
  #
  my $app = AppState->instance;
  $app->initialize( config_dir => './Distribution-Tests');
  $app->check_directories;

  #-----------------------------------------------------------------------------
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

  $log->add_tag('MXT');

  #-------------------------------------------------------------------------------
  # Setup matrix file
  #
  my $cfm = $app->get_app_object('ConfigManager');
  $cfm->initialize;
  $cfm->add_config_object( 'Matrix'
  		       , { store_type	=> 'Yaml'
			 , location	=> $cfm->C_CFF_WORKDIR
			 , requestFile	=> 'Matrix'
			 }
		       );
  $cfm->load;
  $cfm->set_documents([]) unless $cfm->nbr_documents;
#  $cfm->set_value( "Matrix", {}) unless $cfm->get_value("Matrix");

  $log->show_on_warning(1);

  $cfm->add_config_object( 'Project'
  		       , { store_type	=> 'Yaml'
			 , location	=> $cfm->C_CFF_FILEPATH
			 , requestFile	=> 'Project'
			 }
		       );

  my $sts = $self->loadProjectConfig( $log, $cfm);
  $self->leave unless $sts;
}

#-------------------------------------------------------------------------------
# Create Main object
#
my $self = main->new;

#-------------------------------------------------------------------------------
my $app = AppState->instance;
my $log = $app->get_app_object('Log');
my $cfm = $app->get_app_object('ConfigManager');

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
		, $self->usage, $self->examples
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
# If show check prove and critic for the selection about what to show.
# Keep this test before tests on prove or critic
#
elsif( $cmd->getOption('show') )
{
  if( $cmd->getOption('prove') )
  {
    $self->showProveInfo;
  }

  elsif( $cmd->getOption('metric') )
  {
    $self->showMetricInfo;
  }

  elsif( $cmd->getOption('critic') )
  {
    $self->showCriticInfo;
  }
}

#-------------------------------------------------------------------------------
#
#elsif( $cmd->getOption('') )
#{
#}

#-------------------------------------------------------------------------------
# Because critic has been set to a default value, test prove first
#
elsif( $cmd->getOption('prove') )
{
  my $results = $self->testDistribution;
  $self->saveTestResults( $results);

  say "\nTests done on $OSNAME with perl version $PERL_VERSION\n";
}

#-------------------------------------------------------------------------------
#
elsif( $cmd->getOption('metric') )
{
  my $results = $self->metricsOfDistribution;
  $self->saveMetricResults($results);
}

#-------------------------------------------------------------------------------
#
elsif( $cmd->getOption('critic') )
{
  my $results = $self->critisizeDistribution;
  $self->saveCriticResults($results);
}



$self->leave;

#-------------------------------------------------------------------------------
# Cleanup and leave
#
sub leave
{
  my $app = AppState->instance;
  $app->cleanup;
  exit(0);
}

#-------------------------------------------------------------------------------
#
sub loadProjectConfig
{
  my( $self, $log, $cfm) = @_;

  my $sts = 0;
  $cfm->select_config_object('Project');
  if( $log->get_last_error == $cfm->C_CFM_CFGSELECTED )
  {
    $cfm->load;
    if( $log->get_last_error == $cfm->C_CIO_DESERIALFAIL )
    {
      my $f = $cfm->configFile;
      $f =~ s@.*?([^/]+)$@$1@;

      $log->write( "Problems reading project file $f, abort ..."
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
sub testDistribution
{
  my($self) = @_;

  my $app = AppState->instance;
  my $cfm = $app->get_app_object('ConfigManager');
  my $cmd = $app->get_app_object('CommandLine');
  my @args = $cmd->get_arguments;

  my @results;

  $cfm->select_config_object('Project');
  $cfm->select_document(0);
  my $moduleNames = $cfm->get_value('/Tests');
  for( my $mti = 0; $mti <= $#{$moduleNames}; $mti++)
  {
    my $moduleName = $moduleNames->[$mti]{Module};

    next if @args and !($moduleName ~~ @args);

#    my( @states, @tPrgs);
    my @tPrgs;

    say "\nTesting module $moduleName using" unless $cmd->getOption('quiet');
    my $testPrograms = $cfm->get_value( "/TestPrograms", $moduleNames->[$mti]);
    foreach my $testProgram (@$testPrograms)
    {
      if( -r $testProgram )
      {
        # Need to test the program only once
        #
        if( $self->program_tested($testProgram) )
        {
          say "   program $testProgram tested before";
          next;
        }

	say "   program $testProgram" unless $cmd->getOption('quiet');
	push @tPrgs, $testProgram;
        my $state = $self->prove($testProgram);
        $self->set_tested_program( $testProgram => $state);
#	push @states, $state;
      }

      else
      {
        $self->_log( "Test program $testProgram not found"
	           , $self->C_TESTFILENTFND
		   );
      }
    }

#    print "\n";
#    my $state = $self->prove(@tPrgs);
#    say "Outcome: of tests for $moduleName: ", ($state ? 'Success' : 'Failed');


#    push @results, [ $moduleName, \@tPrgs, \@states];
    push @results, [ $moduleName, \@tPrgs];
  }

  return \@results;
}

#-------------------------------------------------------------------------------
# Set prove module
#
sub prove
{
  my( $self, $testProgram) = @_;

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');

  my $prove = App::Prove->new;

  $prove->process_args(@ARGV);
  $prove->verbose($cmd->getOption('verbose'));
#  $prove->quiet(1);
  $prove->lib($cmd->getOption('lib'));
  $prove->comments($cmd->getOption('comments'));
  $prove->blib($cmd->getOption('blib'));
  $prove->merge(1);
  $prove->argv([$testProgram]);
#  $prove->state([qw( failed all save)]);

  #-----------------------------------------------------------------------------
  my $state = $prove->run;

  return $state;
}

#-------------------------------------------------------------------------------
# Save results
#
sub saveTestResults
{
  my( $self, $results) = @_;

  my $app = AppState->instance;

  my $cfm = $app->get_app_object('ConfigManager');
  $cfm->select_config_object('Matrix');
  $cfm->add_documents({}) unless $cfm->nbr_documents;
  $cfm->select_document(0);

  foreach my $result (@$results)
  {
    my $module = $result->[0];
    my $runPerlVersion = $self->setPrimeModuleInfo($module);

    for( my $i = 0; $i <= $#{$result->[1]}; $i++)
    {
#say "Matrix/$module/$OSNAME/Perl/$runPerlVersion = $result->[1][$i]";
      $cfm->set_kvalue( "Matrix/$module/$OSNAME/Perl/$runPerlVersion"
		     , $result->[1][$i]
		     , $self->get_tested_program($result->[1][$i])
                       ? 'Ok'
                       : 'Failed'
		     );
    }
  }

  $cfm->save;
}

#-------------------------------------------------------------------------------
# Set basic module information
#
sub setPrimeModuleInfo
{
  my( $self, $module_name) = @_;

  my $app = AppState->instance;
  my $cfm = $app->get_app_object('ConfigManager');

  my $version = $self->getModuleVersion($module_name);
  my $minPerlVersion = 'v'
    		     . join( '.', @{$self->getPerlMinimalVersion($module_name)
		                         ->{version}
				   }
			   );
  my $runPerlVersion = 'v' . join( '.', @{$PERL_VERSION->{version}});

  $cfm->set_value( "Matrix/$module_name/ModuleVersion", $version);
  $cfm->set_value( "Matrix/$module_name/MinimalPerlVersion", $minPerlVersion);
  return $runPerlVersion;
}

#-------------------------------------------------------------------------------
# Get version of module
#
sub getModuleVersion
{
  my( $self, $module_name) = @_;

  my $version;
  my $code =<<EOCODE;
use $module_name;
\$version = defined \$${module_name}::VERSION // '0';
EOCODE
  eval($code);

  return $version;
}

#-------------------------------------------------------------------------------
# Get minimal perl version of module
#
sub getPerlMinimalVersion
{
  my( $self, $module_name) = @_;

  $module_name =~ s@::@/@g;
  $module_name =~ s@:$@@;
  $module_name = "lib/$module_name.pm";
  my $versionCheckObject = Perl::MinimumVersion->new($module_name);
  my $version = $versionCheckObject->minimum_version if defined $versionCheckObject;
#say "Minimum perl version to use $module_name is $version";

  return $version;
}

#-------------------------------------------------------------------------------
#
sub metricsOfDistribution
{
  my($self) = @_;

  my $app = AppState->instance;

  my $cmd = $app->get_app_object('CommandLine');
  my @args = $cmd->get_arguments;

  my @results;

  my $cfm = $app->get_app_object('ConfigManager');
  $cfm->select_config_object('Project');
  $cfm->select_document(0);
  my $moduleNames = $cfm->get_value('/Tests');

  for( my $mti = 0; $mti <= $#{$moduleNames}; $mti++)
  {
    my $moduleName = $moduleNames->[$mti]{Module};
    next if @args and !($moduleName ~~ @args);

    my $module = $moduleName;
    $module =~ s@::@/@g;
    $module = "lib/$module.pm";


    my $methods = {};
    my $constructor = $moduleNames->[$mti]{Constructor};
#say "Obj: $moduleName->$constructor";

    my $code = '';
    $code = 'use lib qw(lib);' if $cmd->optionExists('lib');
    $code = "require $moduleName;";
    eval($code);
    
    my $newObj = $moduleName->$constructor;
    if( $newObj->can('meta') )
    {
      my $meta = $newObj->meta;
#say "Obj: $newObj, $meta";
      my @methods = sort map {$_->fully_qualified_name;} $meta->get_all_methods;
#      say "Subs;";

      foreach my $sub (@methods)
      {
        next unless $sub =~ m/^${moduleName}::[^:]+$/;
        my $mccabe = 0;# = Perl::Critic::Utils::McCabe->calculate_mccabe_of_sub($sub);
#        say "    $mccabe $sub";
        $methods->{$sub} = {mccabe => 0};
      }
    }

    else
    {
      # No Moose environment ...
    }



    push @results, [ $moduleName, $methods];#, $config];
  }

  return \@results;
}

#-------------------------------------------------------------------------------
#
sub saveMetricResults
{
  my( $self, $results) = @_;

  my $app = AppState->instance;
  my $cfm = $app->get_app_object('ConfigManager');

  $cfm->select_config_object('Matrix');
  $cfm->add_documents({}) unless $cfm->nbr_documents;
  $cfm->select_document(0);

  foreach my $result (@$results)
  {
    my $module = $result->[0];
#    my $runPerlVersion = $self->setPrimeModuleInfo($module);

    # Set information for each of the methods in the module
    #
    $cfm->set_value( "Matrix/$module/Statistics/Methods", $result->[1]);
  }

  $cfm->save;
}

#-------------------------------------------------------------------------------
#
sub critisizeDistribution
{
  my($self) = @_;

  my $app = AppState->instance;

  my $cmd = $app->get_app_object('CommandLine');
  my @args = $cmd->get_arguments;

  my @results;

  my $cfm = $app->get_app_object('ConfigManager');
  $cfm->select_config_object('Project');
  $cfm->select_document(0);
  my $moduleNames = $cfm->get_value('/Tests');
  for( my $mti = 0; $mti <= $#{$moduleNames}; $mti++)
  {
    my $moduleName = $moduleNames->[$mti]{Module};

    next if @args and !($moduleName ~~ @args);

#    my( $violations, $statistics, $config) = $self->runCritics($moduleName);
#    push @results, [ $moduleName, $violations, $statistics, $config];
    my( $violations, $statistics) = $self->runCritics($moduleName);
    push @results, [ $moduleName, $violations, $statistics];
  }

  return \@results;
}

#-------------------------------------------------------------------------------
# Test for critics
#
sub runCritics
{
  my( $self, $module) = @_;

  my $app = AppState->instance;
  my $cmd = $app->get_app_object('CommandLine');

  $module =~ s@::@/@g;
  $module = "lib/$module.pm";

  my %critic_args = ( -severity =>$cmd->getOption('critic') // 'brutal');
  $critic_args{-theme} = 'core';
  $critic_args{-profile} = 'PerlCriticRc' if -r 'PerlCriticRc';
  my $critic = Perl::Critic->new(%critic_args);
#-theme => 'pbp && bugs && certrec && certrule'
#-theme => 'security && complexity && maintenance'

  my $statistics = $critic->statistics;
#  my $config = $critic->config;
  my @violations = $critic->critique($module);

  return ( \@violations, $statistics);#, $config);
}

#-------------------------------------------------------------------------------
# Save results
#
sub saveCriticResults
{
  my( $self, $results) = @_;

  my $app = AppState->instance;
  my $cfm = $app->get_app_object('ConfigManager');

  $cfm->select_config_object('Matrix');
  $cfm->add_documents({}) unless $cfm->nbr_documents;
  $cfm->select_document(0);

  foreach my $result (@$results)
  {
    my $module = $result->[0];
    my $runPerlVersion = $self->setPrimeModuleInfo($module);
    my @violations = @{$result->[1]};

    $cfm->set_value( "Matrix/$module/Critics", []);
    my $vstore = {};
    foreach my $v (@violations)
    {
      $vstore = { description => $v->description
      		, explanation => $v->explanation
		, line_number => $v->logical_line_number
                , colomn_number => $v->visual_column_number
		, filename => $v->filename
		, severity => $v->severity
		, diagnostics => $v->diagnostics
		, policy => $v->policy
		, source => $v->source
		, element_class => $v->element_class
		};
      $cfm->push_value( "Matrix/$module/Critics", [$vstore]);
    }

    # Set all information for the whole of the module
    #
    my $statistics = $result->[2];
    $cfm->set_value( "Matrix/$module/Statistics/Module", {});
    my $mstat = $cfm->get_value("Matrix/$module/Statistics/Module");
    $cfm->set_value( "Statements", $statistics->statements, $mstat);
#say "MS: $mstat $module";

    $cfm->set_value( "Lines", $statistics->lines, $mstat);
#say "G1: ", $cfm->get_value( "Lines", $mstat);
#say "G2: ", $cfm->get_value( "Matrix/$module/Statistics/Module/Lines");
#next;
    $cfm->set_value( "LBlank", $statistics->lines_of_blank, $mstat);
    $cfm->set_value( "LComment", $statistics->lines_of_comment, $mstat);
    $cfm->set_value( "LData", $statistics->lines_of_data, $mstat);
    $cfm->set_value( "LPerl", $statistics->lines_of_perl, $mstat);
    $cfm->set_value( "LPod", $statistics->lines_of_pod, $mstat);
    $cfm->set_value( "SNoSubs", $statistics->statements_other_than_subs, $mstat);
    $cfm->set_value( "AvMcCabe", $statistics->average_sub_mccabe, $mstat);
    $cfm->set_value( "VSeverity", $statistics->violations_by_severity, $mstat);
    $cfm->set_value( "VPolicy", $statistics->violations_by_policy, $mstat);
    $cfm->set_value( "VTotal", $statistics->total_violations, $mstat);
    $cfm->set_value( "VFile", $statistics->violations_per_file, $mstat);
    $cfm->set_value( "VStatement", $statistics->violations_per_statement, $mstat);
    $cfm->set_value( "VLCode", $statistics->violations_per_line_of_code, $mstat);
  }

  $cfm->save;
}

#-------------------------------------------------------------------------------
#
sub showProveInfo
{
  my($self) = @_;

  # Get the document where the information is to be found
  #
  my $app = AppState->instance;

  my $cfm = $app->get_app_object('ConfigManager');
  $cfm->select_config_object('Matrix');
  $cfm->add_documents({}) unless $cfm->nbr_documents;
  $cfm->select_document(0);

  say sprintf( "\n%-45s %-8s %-9s %-25s %-6s"
      	     , 'Module', 'Version', 'Use Perl', 'Test Program', 'Result'
             );
  say sprintf( "%45s %8s %9s %25s %6s"
      	     , '-' x 45, '-' x 8, '-' x 9, '-' x 25, '-' x 6
	     );

  # Get all tested modules
  #
  my $prevModName = '';
  my $moduleNames = $cfm->get_keys('/Matrix');
  foreach my $module (sort @$moduleNames)
  {
    my $moduleVersion = $cfm->get_value( "/Matrix/$module/ModuleVersion");
    my $minPerlVersion = $cfm->get_value( "/Matrix/$module/MinimalPerlVersion");

    # Get all perl versions under which the software is tested
    #
    my $prevPVersion = '';
    my $perlVersions = $cfm->get_keys("/Matrix/$module/$OSNAME/Perl");
    foreach my $pVersion (sort @$perlVersions)
    {
      # Get all testprograms used to test the module
      #
      my $testPrograms = $cfm->get_keys("/Matrix/$module/$OSNAME/Perl/$pVersion");
      for( my $tpi = 0; $tpi <= $#{$testPrograms}; $tpi++)
      {
        my $tProgram = $testPrograms->[$tpi];
	my $testStatus = $cfm->get_kvalue( "/Matrix/$module/$OSNAME/Perl/$pVersion"
	  				, $tProgram
					);
	say sprintf( "%-45s %-8s %-9s %-25s %-6s"
	  	   , ($prevModName eq $module ? '' : $module)
		   , ($prevModName eq $module ? '' : $moduleVersion)
		   , ($prevPVersion eq $pVersion
		       ? ' '
		       : ($minPerlVersion eq $pVersion
		           ? '*'
			   : ' '
			 ) . $pVersion
		     )
		   , $tProgram, $testStatus
		   );

	$prevModName = $module;
	$prevPVersion = $pVersion;
      }
    }
  }
}

#-------------------------------------------------------------------------------
#
sub showMetricInfo
{
  my($self) = @_;

  # Get the document where the information is to be found
  #
  my $app = AppState->instance;

  my $cfm = $app->get_app_object('ConfigManager');
  $cfm->select_config_object('Matrix');
  $cfm->add_documents({}) unless $cfm->nbr_documents;
  $cfm->select_document(0);

  say sprintf( "\n%-45s %-14s %-9s %-5s"
      	     , 'Module', 'Critic 5-1', 'Av McCabe', '#subs'
             );
  say sprintf( "%45s %14s %9s %5s"
      	     , '-' x 45, '-' x 14, '-' x 9, '-' x 5
	     );

  # Get all tested modules
  #
  my $prevModName = '';
  my $moduleNames = $cfm->get_keys('/Matrix');
  foreach my $module (sort @$moduleNames)
  {
    my $mstat = $cfm->get_value("/Matrix/$module/Statistics/Module");
    my $critic_1to5 =
       join( ','
           , $cfm->get_value( "VSeverity/5", $mstat) // 0
           , $cfm->get_value( "VSeverity/4", $mstat) // 0
           , $cfm->get_value( "VSeverity/3", $mstat) // 0
           , $cfm->get_value( "VSeverity/2", $mstat) // 0
           , $cfm->get_value( "VSeverity/1", $mstat) // 0
           );

#    $mstat = $cfm->get_value("/Matrix/$module/Statistics/Methods");
    my $methods = $cfm->get_keys("/Matrix/$module/Statistics/Methods");

    say sprintf( "%-45s %-14s %9.2f %5d"
	       , ($prevModName eq $module ? '' : $module)
               , $critic_1to5
               , $cfm->get_value( "AvMcCabe", $mstat) // 0
               , scalar(@$methods)
	       );

    $prevModName = $module;
  }
}

#-------------------------------------------------------------------------------
#
sub showCriticInfo
{
  my($self) = @_;

  # Get the document where the information is to be found
  #
  my $app = AppState->instance;

  my $cmd = $app->get_app_object('CommandLine');

  # Get the severity level for which critics must be filtered
  # Severity must be translated to a number
  #
  my $selectSeverity = $cmd->getOption('critic');
  $selectSeverity = $self->cnvSeverityCode($selectSeverity)
    unless $selectSeverity =~ m/^\d+$/;
  $selectSeverity //= 1;

  # Get the modulenames from the argument list
  #
  my @args = $cmd->get_arguments;

  # Get the numbers to select critics for displaying more information
  # on that particular critic
  #
  my $criticNumbers = $cmd->getOption('describe');
  $criticNumbers //= [];
  @$criticNumbers = split( /,/, join( ',', @$criticNumbers));

  # Select the proper document file
  #
  my $cfm = $app->get_app_object('ConfigManager');
  $cfm->select_config_object('Matrix');
  $cfm->add_documents({}) unless $cfm->nbr_documents;
  $cfm->select_document(0);

  # Get all tested modules
  #
  my $moduleNames = $cfm->get_keys('/Matrix');
  foreach my $moduleName (sort @$moduleNames)
  {
    next if @args and !($moduleName ~~ @args);

    say "\nModule: $moduleName";
    say sprintf( "  %-3s %-4s %-3s %1s %-s"
      	       , 'Crt', 'Line', 'Col', 'S', 'Description'
	       );
    say sprintf( "  %3s %4s %3s %1s %s"
      	       , '-' x 3, '-' x 4, '-' x 3, '-', '-' x 30
	       );
    my $critics = $cfm->get_value("/Matrix/$moduleName/Critics");
    for( my $criticCount = 0; $criticCount <= $#{$critics}; $criticCount++)
    {
      # Skip all critics lower than given with critic option
      #
      my $severity = $critics->[$criticCount]{severity};
      next if $severity < $selectSeverity;

      my $line = $critics->[$criticCount]{line_number};
      my $column = $critics->[$criticCount]{colomn_number};
      my $description = $critics->[$criticCount]{description};
#      my = $critics->[$criticCount]{};

      say sprintf( "  %3d %4d %3d %1s %-s"
                 , $criticCount + 1, $line, $column, $severity, $description
		 );
      if( ($criticCount + 1) ~~ @$criticNumbers )
      {
	say "    Policy:        ", $critics->[$criticCount]{policy};
        say "    Element_class: ", $critics->[$criticCount]{element_class};
	say "    Explanation    ", $critics->[$criticCount]{explanation};
	say "    Source         ", $critics->[$criticCount]{source};
        say "\n", $critics->[$criticCount]{diagnostics};
      }
    }
  }
}


#-------------------------------------------------------------------------------


__END__

#-------------------------------------------------------------------------------
#
sub dropViolations
{
  my( $self, $module, $severity) = @_;

# and $severity >= 1 and $severity <= 5
  my @svrty = qw( brutal cruel harsh stern gentle);
  if( $severity !~ m/^\d+$/ and $severity ~~ @svrty )
  {
    my $slvl;
    for( $slvl = 0; $slvl < 5; $slvl++)
    {
      last if $svrty[$slvl] eq $severity;
    }
    $severity = $slvl + 1;
  }

  else
  {
    $self->_log( '', );
    return;
  }
}


#-------------------------------------------------------------------------------
# Check testfiles option
#
elsif( $cmd->getOption('testfiles') )
{
  $cfm->select_config_object('Project');
  $cfm->select_document(0);

  my $moduleNames = $cfm->get_keys('/Tests');
  foreach my $moduleName (@$moduleNames)
  {
    say "\nTesting module $moduleName using";
    my $testPrograms = $cfm->get_kvalue( '/Tests', $moduleName);
    foreach my $testProgram (@$testPrograms)
    {
      $testProgram = "t/$testProgram" unless -r $testProgram;
      say "   program t/$testProgram";
    }
  }

  $self->leave;
}
