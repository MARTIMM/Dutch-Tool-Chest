#!/usr/bin/perl
#
use Modern::Perl;
use version; our $VERSION = version->parse('0.0.1');
use namespace::autoclean;

use Moose;
extends qw(AppState::Ext::Constants);

use AppState;
require Tk;
use Tk::Labelframe;

#-------------------------------------------------------------------------------
# Program information
#
has description =>
    ( is                => 'ro'
    , isa               => 'Str'
    , default           => <<EODSCR
Program to edit the Project.yml file in the directory of a distribution.
Furthermore it helps generating documentation from the data in the yaml file,
build and test the distribution and much more using the known Perl modules
such as Perl::Critic, App::Prove, Software::License, PPI, Module::Build and
many more.
EODSCR
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
        ]
      }
    , init_arg          => undef
    , lazy              => 1
    );

has examples =>
    ( is                => 'ro'
    , isa               => 'ArrayRef'
    , default           =>
      sub
      { return
        [ [ "cd MyDistro-Project; $0" => <<EOTXT
Run the progran in the directory when the Project.yml is generated. Then
start the program.
EOTXT
          ]
        ];
      }
    , init_arg          => undef
    , lazy              => 1
    );

# Main window
#
has main_window =>
    ( is                => 'ro'
    , isa               => 'Tk::MainWindow'
    , default           =>
      sub
      { return Tk::MainWindow->new(-title => 'Edit Project');
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
#    $self->code_reset;
#    $self->const( 'C_PROJECTREADERR',  'M_ERROR');
#    $self->const( 'C_TESTFILENTFND',   'M_F_WARNING');
#    $self->const( 'C_EVALERR',         'M_F_WARNING');

    $self->meta->make_immutable;
  }

  #-----------------------------------------------------------------------------
  # Setup application
  #
  my $app = AppState->instance;
  $app->initialize( use_temp_dir => 0, use_work_dir => 0);
  $app->check_directories;

  #-----------------------------------------------------------------------------
  # Setup logging
  #
  my $log = $app->get_app_object('Log');

  #$log->show_on_error(0);
  $log->do_append_log(0);
  $log->start_logging;

  #$log->do_flush_log(1);
  $log->log_mask($self->M_ERROR|$self->M_WARNING);
#  $log->log_mask($self->M_ERROR|$self->M_WARNING|$self->M_INFO);

  $log->add_tag('EPR');
}

#-------------------------------------------------------------------------------
# Create Main object
#
my $self = main->new;

#-------------------------------------------------------------------------------
$self->open_files;

$self->create_editor_windows;
$self->main_window->MainLoop;

#-------------------------------------------------------------------------------
#
sub open_files
{
  my( $self) = @_;

  my $app = AppState->instance;
  
}

#-------------------------------------------------------------------------------
#
sub create_editor_windows
{
  my( $self) = @_;
  
  $self->create_menubar;
  $self->create_panes;
  my $mw = $self->main_window;
}

#-------------------------------------------------------------------------------
#
sub create_menubar
{
  my( $self) = @_;
 
  my $mw = $self->main_window;
  my $menubar = $mw->Menu( -type => 'menubar');
  $mw->configure(-menu => $menubar);

  # File menu: Save, Exit
  #
  my $file_menu = $menubar->cascade( -label => 'File'
			           , -tearoff => 0
				   );

  $file_menu->command( -command => sub {}
                     , -label => 'Save'
                     , -state => 'disabled'
                     );

  $file_menu->command( -command => sub { $self->main_window->destroy; }
                     , -label => 'Exit'
                     );

  # Help menu: Index, About
  #
  my $help_menu = $menubar->cascade( -label => 'Help'
			           , -tearoff => 0
				   );

  $help_menu->command( -command => sub {}
                     , -label => 'Index'
                     , -state => 'disabled'
                     );

  $help_menu->command( -command => sub {}
                     , -label => 'About'
                      , -state => 'disabled'
                    );
}

#-------------------------------------------------------------------------------
#
sub create_panes
{
  my( $self) = @_;

  my $mw = $self->main_window;
  my $pw = $mw->Panedwindow(-orient => 'horizontal')
              ->pack( -expand => 1, -fill => 'both');

  # Show the Project.yml contents
  #
  my $f1 = $mw->Labelframe( -width => 300, -height => 500
                          , -text => 'Project.yml'
                          )
              ->pack( -side => 'top', -fill => 'x');
  $pw->add($f1);

  # Show the Directory contents
  #
  my $f2 = $mw->Labelframe( -width => 300, -height => 500
                          , -text => 'Distribution directory'
                          )
              ->pack( -side => 'top', -fill => 'x');
  $pw->add($f2);

  # Show the scrutinize results
  #
  my $f3 = $mw->Labelframe( -width => 300, -height => 500
                          , -text => 'Test results'
                          )
              ->pack( -side => 'top', -fill => 'x');
  $pw->add($f3);
  
}



