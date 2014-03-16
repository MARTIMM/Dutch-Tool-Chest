#!/usr/bin/perl
#-------------------------------------------------------------------------------

=head1 NAME

removeHardTabs - Program to substitute hardtabs with spaces

=head1 SYNOPSIS

  # removeHardTabs Directory-File {Directory-File ...}

=head1 DESCRIPTION

Remove hardtabs from one or more documents. Also any trailing blancs on a single
line are removed as a by product. The arguments can be a directory or a
filename. The directory is recursively processed and will modify files which
have the extensions .pl, .pm, .yml or .t. When the argument is a file it will
only process that one file if it is of the proper type

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

use Text::Tabs ();
use File::Find ();
use File::Type;

say "\nReplace all occurences of hard tabs with spaces\n";
my $regex_mime_type_test = qr@application/(x-perl|octet-stream)@;

File::Find::find( { wanted => \&removeHardTabs
                  }
                , @ARGV
                );

exit(0);

#-------------------------------------------------------------------------------
#
sub removeHardTabs
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
  $text = Text::Tabs::expand($text);
  $text =~ s/[ ]+\n/\n/g;
  my $txt1 = $text;

  if( $txt0 ne $txt1 )
  {
    say "$dir/$file modified";

    open $F, '>', $file;
    print $F $text;
    close $F;
  }
}



