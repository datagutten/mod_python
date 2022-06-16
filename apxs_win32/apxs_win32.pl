#!C:/Perl/bin/perl
use strict;
use warnings;
use Getopt::Long;
require Win32;
use Config;
use ExtUtils::MakeMaker;
use File::Spec::Functions;
require 'util.pl';
my ($apache, $help, $progname);
GetOptions( 'with-apache2=s' => \$apache,
	    'with-apache-prog=s' => \$progname,
	    'help' => \$help,
	    ) or usage($0);
usage($0) if $help;

unless (defined $apache and -d $apache) {
    $apache = prompt("Please give the path to your Apache2 installation:",
		     $apache);
}
die "Can't find a suitable Apache2 installation!" 
    unless (-d $apache and check_httpd($apache, $progname));

$apache = Win32::GetShortPathName($apache);

my $perl = which('perl');
my %subs_cfg = (
                '%APACHE2%' => $apache,
                '%PROGNAME%' => $progname,
                '%AWK%' => which('awk') || which('gawk') || '',
                '%CC%' => $Config{cc},
                '%CPP%' => $Config{cpp},
                '%SHELL%' => $ENV{COMSPEC},
                '%LD%' => $Config{ld},
               );

my $pat = join '|', keys %subs_cfg;
my $build_dir = catdir $apache, 'build';
my $cfg_mk = catfile $build_dir, 'config_vars.mk';
unless (-d $build_dir) {
    mkdir $build_dir or die "Cannot mkdir $build_dir: $!";
}

my $prefix = $apache;
my $exec_prefix = $prefix;
my $datadir = ${prefix};
my $localstatedir = ${prefix};

my ($aprutil_libname, $apr_libname);
my $libdir = catdir $exec_prefix, 'lib';
opendir(my $apr_dir, $libdir) or die "Cannot opendir $libdir: $!";
my @libs = readdir $apr_dir;
closedir $apr_dir;
foreach (@libs) {
    if (/^libaprutil\b\S+lib$/) {
        $aprutil_libname = $_;
        next;
    }
    if (/^libapr\b\S+lib$/) {
        $apr_libname = $_;
        next;
    }
}
die "Cannot determine apr lib names" 
    unless ($aprutil_libname and $apr_libname);

my %dirs = (prefix => $prefix,
            exec_prefix => $exec_prefix,
            datadir => $datadir,
            localstatedir => $localstatedir,
            bindir => catdir($exec_prefix, 'bin'),
            sbindir => catdir($exec_prefix, 'bin'),
            cgidir => catdir($datadir, 'cgi-bin'),
            logfiledir => catdir($localstatedir, 'logs'),
            mandir => catdir($prefix, 'man'),
            libdir => $libdir,
            libexecdir => catdir($exec_prefix, 'modules'),
            htdocsdir => catdir($datadir, 'htdocs'),
            manualdir => catdir($datadir, 'manual'),
            includedir => catdir($prefix, 'include'),
            errordir => catdir($datadir, 'error'),
            iconsdir => catdir($datadir, 'icons'),
            sysconfdir => catdir($prefix, 'conf'),
            installbuilddir => catdir($datadir, 'build'),
            runtimedir => catdir($localstatedir, 'logs'),
            proxycachedir => catdir($localstatedir, 'proxy'),
            APR_BINDIR => catdir($apache, 'bin'),
            APU_BINDIR => catdir($apache, 'bin'),
            APR_INCLUDEDIR => catdir($apache, 'include'),
            APU_INCLUDEDIR => catdir($apache, 'include'),
            APRUTIL_LIBNAME => catfile($libdir, $aprutil_libname),
            APR_LIBNAME => catfile($libdir, $apr_libname),
          );

open(my $cfg, ">$cfg_mk")
    or die qq{Cannot open $cfg_mk: $!};
while (<DATA>) {
    if (/^rel_(\S+) = (\S+)/) {
        my $dir = $1; next unless $dir;
        my $val = $2;
        print $cfg $_;
        print $cfg "exp_$dir = ", catdir($apache, $val), $/;
        next;
    }
    s/($pat)/$subs_cfg{$1}/;
    print $cfg $_;
}
foreach (keys %dirs) {
    print $cfg "$_ = $dirs{$_}\n";
}
close $cfg;

my %subs_apxs = (
                 '%perlbin%' => which('perl'),
                 '%exp_installbuilddir%' => $build_dir,
                 '%RM_F%' => qq{$perl -MExtUtils::Command -e rm_f},
                 '%CP%' => qq{$perl -MExtUtils::Command -e cp},
                 '%CHMOD%' => qq{$perl -MExtUtils::Command -e chmod},
                 '%TOUCH%' => qq{$perl -MExtUtils::Command -e touch},
                 );
$pat = join '|', keys %subs_apxs;
my $apxs_out = catfile $apache, 'bin', 'apxs.pl';
my $apxs_in = 'apxs_win32';
open(my $out, ">$apxs_out")
    or die "Cannot open $apxs_out: $!";
open(my $in, $apxs_in)
    or die "Cannot open $apxs_in: $!";
while (<$in>) {
    s/($pat)/$subs_apxs{$1}/;
    print $out $_;
}
close $in;
close $out;

system ('pl2bat', $apxs_out) == 0 
    or die "system pl2bat $apxs_out failed: $?";
print qq{\napxs.bat has been created under $apache\\bin.\n\n};

__DATA__
exp_exec_prefix = %APACHE2%
rel_exec_prefix =
rel_bindir = bin
rel_sbindir = bin
rel_libdir = lib
rel_libexecdir = modules
rel_sysconfdir = conf
rel_datadir =
rel_installbuilddir = build
rel_errordir = error
rel_iconsdir = icons
rel_htdocsdir = htdocs
rel_manualdir = manual
rel_cgidir = cgi-bin
rel_includedir = include
rel_localstatedir =
rel_runtimedir = logs
rel_logfiledir = logs
rel_proxycachedir = proxy
SHLTCFLAGS = 
LTCFLAGS =
MPM_NAME = winnt
MPM_SUBDIR_NAME = winnt
htpasswd_LTFLAGS =
htdigest_LTFLAGS =
rotatelogs_LTFLAGS =
logresolve_LTFLAGS =
htdbm_LTFLAGS =
ab_LTFLAGS =
checkgid_LTFLAGS =
APACHECTL_ULIMIT =
progname = %PROGNAME%
MPM_LIB = server/mpm/winnt/
OS = win32
OS_DIR = win32
BUILTIN_LIBS =
SHLIBPATH_VAR = 
OS_SPECIFIC_VARS =
PRE_SHARED_CMDS =
POST_SHARED_CMDS = 
shared_build =
AP_LIBS =
AP_BUILD_SRCLIB_DIRS = apr apr-util
AP_CLEAN_SRCLIB_DIRS = apr-util apr
abs_srcdir = 
sysconf = httpd.conf
other_targets =
unix_progname = httpd
prefix = %APACHE2%
AWK = %AWK%
CC = %CC%
LD = %LD%
CPP = %CPP%
CXX =
CPPFLAGS =
CFLAGS = /nologo /MD /W3 /O2 /D WIN32 /D _WINDOWS /D NDEBUG
CXXFLAGS =
LTFLAGS =
LDFLAGS = kernel32.lib /nologo /subsystem:windows /dll /libpath:"%APACHE2%\lib"
LT_LDFLAGS = 
SH_LDFLAGS =
HTTPD_LDFLAGS =
UTIL_LDFLAGS =
LIBS =
DEFS =
INCLUDES =
NOTEST_CPPFLAGS = 
NOTEST_CFLAGS =
NOTEST_CXXFLAGS =
NOTEST_LDFLAGS =
NOTEST_LIBS =
EXTRA_CPPFLAGS = 
EXTRA_CFLAGS = 
EXTRA_CXXFLAGS =
EXTRA_LDFLAGS =
EXTRA_LIBS =
EXTRA_INCLUDES = 
LIBTOOL = 
SHELL = %SHELL%
MODULE_DIRS = aaa filters loggers metadata proxy http generators mappers
MODULE_CLEANDIRS = arch/win32 cache echo experimental ssl test dav/main dav/fs
PORT = 80
nonssl_listen_stmt_1 =
nonssl_listen_stmt_2 = Listen @@Port@@
CORE_IMPLIB_FILE =
CORE_IMPLIB =
SH_LIBS =
SH_LIBTOOL =
MK_IMPLIB =
INSTALL_PROG_FLAGS =
DSO_MODULES =
