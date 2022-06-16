use File::Spec::Functions;

sub usage {
    my $script = shift;
    print <<"END";

 Usage: perl $script [--with-apache2=C:\Path\to\Apache2]
        perl $script [--with-apache-prog=httpd.exe]
        perl $script --help

Options:

  --with-apache2=C:\Path\to\Apache2 : specify the top-level Apache2 directory
  --with-apache-prog=Apache.exe     : specify the Apache2 program name
  --help                            : print this help message

With no options specified, an attempt will be made to find a suitable 
Apache2 directory with a program name of "Apache.exe".

END
    exit;
}

sub check_httpd {
  my ($apache, $progname) = @_;

  die qq{No libhttpd library found under $apache/lib}
    unless -e qq{$apache/lib/libhttpd.lib};

  die qq{No httpd header found under $apache/include}
    unless -e qq{$apache/include/httpd.h};

  my $vers = qx{"$apache/bin/$progname" -v};
  die qq{"$apache" does not appear to be version 2}
    unless $vers =~ m!Apache/2!;

  return 1;
}

sub check_apr {
  (my $prefix) = @_;
  my ($dir);

  my $lib = catdir $prefix, 'lib';
  opendir($dir, $lib) or die qq{Cannot opendir $lib: $!};
  my @libs = grep /^libapr\b\S+lib$/, readdir $dir;
  closedir $dir;
  die qq{Unable to find apr lib beneath $lib} unless (scalar @libs > 0);

  die qq{No apr.h header found under $prefix/include}
    unless -e qq{$prefix/include/apr.h};

  my $bin = catdir $prefix, 'bin';
  opendir($dir, $bin) or die qq{Cannot opendir $bin: $!};
  my @bins = grep /^libapr\b\S+dll$/, readdir $dir;
  closedir $dir;
  die qq{Unable to find apr dll beneath $bin} unless (scalar @bins > 0);

  return 1;
}

sub check_apu {
  (my $prefix) = @_;
  my ($dir);

  my $lib = catdir $prefix, 'lib';
  opendir($dir, $lib) or die qq{Cannot opendir $lib: $!};
  my @libs = grep /^libaprutil\b\S+lib$/, readdir $dir;
  closedir $dir;
  die qq{Unable to find aprutil lib beneath $lib} unless (scalar @libs > 0);

  die qq{No apu.h header found under $prefix/include}
    unless -e qq{$prefix/include/apu.h};

  my $bin = catdir $prefix, 'bin';
  opendir($dir, $bin) or die qq{Cannot opendir $bin: $!};
  my @bins = grep /^libaprutil\b\S+dll$/, readdir $dir;
  closedir $dir;
  die qq{Unable to find aprutil dll beneath $bin} unless (scalar @bins > 0);

  return 1;
}
 
1;
