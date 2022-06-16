#!C:/Perl/bin/perl
use strict;
use warnings;
use Getopt::Long;
require Win32;
use Config;
use ExtUtils::MakeMaker;
use File::Basename;
use File::Spec::Functions;
require 'util.pl';

BEGIN {
  die 'This script is intended for Win32' unless $^O =~ /Win32/i;
}

my ($apache, $help, $progname);
GetOptions( 'with-apache2=s' => \$apache,
	    'with-apache-prog=s' => \$progname,
	    'help' => \$help,
	    ) or usage($0);
usage($0) if $help;

my @path_ext;
path_ext();
($apache, $progname) = search($apache, $progname);

push @ARGV, "--with-apache-prog=$progname";

for my $file (qw(apxs_win32.pl apr_win32.pl apu_win32.pl) ) {
  push @ARGV, "--with-apache2=$apache";
  unless (my $return = do $file) {
    die "Cannot parse $file: $@" if $@;
    die "Cannot do $file: $!"    unless defined $return;
    die "Cannot run $file"       unless $return;
  }
}

sub search {
  my ($apache, $progname) = @_;
  
  if ($apache) {
    die qq{Cannot find the "$apache" directory} unless -d $apache;
    if ($progname) {
      my $bin = catfile $apache, 'bin', $progname;
      die qq{"$bin" appears not to be an executable file} unless (-x $bin);
    }
    else {
      $progname = 'Apache.exe';
    }
    if (check_httpd($apache, $progname)) {
      $apache = Win32::GetShortPathName($apache);
      $apache =~ s!\\$!!;
      return ($apache, $progname);
    }
    else {
      die qq{"$apache" appears not to be a suitable Apache2 installation};
    }
  }

  for my $binary( qw(Apache.exe httpd.exe) ) {
    my ($candidate, $bin);
    if ($bin = which($binary)) {
      ($candidate = dirname($bin)) =~ s!bin$!!;
      if (-d $candidate and check_httpd($candidate, $binary)) {
        $apache = $candidate;
        $progname = $binary;
        last;
      }
    }
  }

  $progname ||= 'Apache.exe';

  unless ($apache and -d $apache) {
    $apache = prompt("Please give the path to your Apache2 installation:",
                     $apache);
    $progname = prompt("Please give the name of your Apache program name:",
                       $progname);
  }
  die "Cannot find a suitable Apache2 installation!" 
    unless ($apache and -d $apache and check_httpd($apache, $progname));
  
  $apache = Win32::GetShortPathName($apache);
  $apache =~ s!\\$!!;
  my $ans = prompt(qq{\nUse "$apache" for your Apache2 directory?}, 'yes');
  unless ($ans =~ /^y/i) {
    die <<'END';

Please run this configuration script again, and give
the --with-apache2=C:\Path\to\Apache2 option to specify
the desired top-level Apache2 directory and, if necessary,
the --with-apache-prog=httpd.exe to specify the Apache
program name.

END
  }
  return ($apache, $progname);
}

sub drives {
  my @drives = ();
  eval{require Win32API::File;};
  return map {"$_:\\"} ('C' .. 'Z') if $@;
  my @r = Win32API::File::getLogicalDrives();
  return unless @r > 0;
  for (@r) {
    my $t = Win32API::File::GetDriveType($_);
    push @drives, $_ if ($t == 3 or $t == 4);
  }
  return @drives > 0 ? @drives : undef;
}

sub path_ext {
  if ($ENV{PATHEXT}) {
    push @path_ext, split ';', $ENV{PATHEXT};
    for my $ext (@path_ext) {
      $ext =~ s/^\.*(.+)$/$1/;
    }
  }
  else {
    #Win9X: doesn't have PATHEXT
    push @path_ext, qw(com exe bat);
  }
}

sub which {
  my $program = shift;
  return unless $program;
  my @extras = ();
  my @drives = drives();
  if (@drives > 0) {
    for my $drive (@drives) {
      for ('Apache2', 'Program Files/Apache2',
           'Program Files/Apache Group/Apache2') {
        my $bin = catfile $drive, $_, 'bin';
        push @extras, $bin if (-d $bin);
      }
    }
  }
  my @a = map {catfile($_, $program) } (path(), @extras);
  for my $base(@a) {
    return $base if -x $base;
    for my $ext (@path_ext) {
      return "$base.$ext" if -x "$base.$ext";
    }
  }
  return;
}
