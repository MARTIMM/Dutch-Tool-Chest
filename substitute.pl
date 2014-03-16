#!/usr/bin/perl
#-------------------------------------------------------------------------------

=head1 NAME

substitute - Program to substitute a given identifier with another

=head1 SYNOPSIS

  # substitute search-word replacement-word directory-File {Directory-File ...}

=head1 DESCRIPTION

Substitute identifiers with another in one or more documents. The first two
arguments are the searched word and replacement word. These can only contain
alphanumeric characters or underscores ('_'). The arguments following next are
directories or files. The directory is recursively processed and will modify
files which have the extensions .pl, .pm, .yml or .t. When the argument is a
file it will only process that one file if it is of the proper type.

PLEASE BACKUP BEFORE ATTEMPTING TO USE THE PROGRAM!

=head1 AUTHOR

Marcel Timmerman, E<lt>mt1957@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Marcel Timmerman

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.3 or,
at your option, any later version of Perl 5 you may have available.

See <http://www.perl.com/perl/misc/Artistic.html>

=cut

#-------------------------------------------------------------------------------
#
use Modern::Perl;
use File::Find ();
use File::Type;

my $searchWord = shift @ARGV;
if( $searchWord !~ m/\w+/ )
{
  say 'Search word may only contain letters digits and underscores';
  exit(1);
}

my $replaceWord = shift @ARGV;
if( $replaceWord !~ m/\w+/ )
{
  say 'Replace word may only contain letters digits and underscores';
  exit(1);
}

say "\nReplace all occurences of '$searchWord' with '$replaceWord'\n";

my $substitute_ok = 0;
my $found_search = 0;
my $regex_mime_type_test = qr@application/(x-perl|octet-stream)@;

File::Find::find( { wanted => \&search }, @ARGV );

if( $found_search )
{
  local $\ = undef;
  print "\nDo you like to substitute the words in the list found above ? > ";
  my $answer = <STDIN>;
  $substitute_ok = ($answer =~ m/^y(es)?$/is) ? 1 : 0;
  print "\n";

  File::Find::find( { wanted => \&substitute }, @ARGV ) if $substitute_ok;
  print "\n";
}

exit(0);

#-------------------------------------------------------------------------------
#
sub search
{
  my $dir = $File::Find::dir;
  my $file = $_;

  return if -d $file;

  my $ft = File::Type->new;
  my $mime_type = $ft->mime_type($file);
#say "T: $file = $mime_type";
  return unless $mime_type =~ m/$regex_mime_type_test/s;

#  return unless $file =~ m/.*?\.(pl|pm|yml|t|txt)$/s or -T $file;

  local $/ = undef;
  open my $F, '<', $file;
  my $text = <$F>;
  close $F;

  my(@nbrSubs) = $text =~ m/\b($searchWord)\b/g;
  if( @nbrSubs )
  {
    my $times = @nbrSubs == 1 ? 'time' : 'times';
    say "Found " . scalar(@nbrSubs) . " $times $searchWord in $dir/$file";
    $found_search = 1;
  }
}

#-------------------------------------------------------------------------------
#
sub substitute
{
  my $dir = $File::Find::dir;
  my $file = $_;

  return if -d $file;

  my $ft = File::Type->new;
  my $mime_type = $ft->mime_type($file);
#say "T: $file = $mime_type";
  return unless $mime_type =~ m/$regex_mime_type_test/s;

#  return unless $file =~ m/.*?\.(pl|pm|yml|t|txt)$/s;

  local $/ = undef;
  open my $F, '<', $file;
  my $text = <$F>;
  close $F;

  my $txt0 = $text;
  $text =~ s/\b$searchWord\b/$replaceWord/g;
  my $txt1 = $text;

  if( $txt0 ne $txt1 )
  {
    say "$dir/$file modified";

    open $F, '>', $file;
    print $F $text;
    close $F;
  }
}



