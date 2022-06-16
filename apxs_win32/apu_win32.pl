#!perl
use strict;
use Config;
use Getopt::Long;
require Win32;
use ExtUtils::MakeMaker;
use File::Spec::Functions qw(catfile catdir);
use warnings;
require 'util.pl';

BEGIN {
    die 'This script is intended for Win32' unless $^O =~ /Win32/i;
}

my $license = <<'END';
# ====================================================================
#
#  Copyright 2003-2004  The Apache Software Foundation
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# ====================================================================
#
# APR-util script designed to allow easy command line access to APR-util
# configuration parameters.

END

my ($prefix, $help);
GetOptions('with-apache2=s' => \$prefix, 'help' => \$help) or usage($0);
usage($0) if $help;

unless (defined $prefix and -d $prefix) {
    $prefix = prompt("Please give the path to your Apache2 installation:",
		     $prefix);
}
die "Can't find a suitable Apache2 installation!" 
    unless (-d $prefix and check_apu($prefix));

$prefix = Win32::GetShortPathName($prefix);

my %ap_dir;
foreach (qw(bin lib include build)) {
    $ap_dir{$_} = catdir $prefix, $_;
}

my $apu_version = catfile $ap_dir{include}, 'apu_version.h';
open(my $inc, $apu_version)
    or die "Cannot open $apu_version: $!";
my %vers;
while (<$inc>) {
    if (/define\s+APU_(MAJOR|MINOR|PATCH)_VERSION\s+(\d+)/) {
        $vers{$1} = $2;
    }
}
close $inc;
my $file = $vers{MAJOR} < 1 ? "apu-config.pl" : "apu-$vers{MAJOR}-config.pl";

my $dotted = "$vers{MAJOR}.$vers{MINOR}.$vers{PATCH}";

my $aprutil_libname;
opendir(my $dir, $ap_dir{lib}) or die "Cannot opendir $ap_dir{lib}: $!";
my @libs = grep /^libaprutil\b\S+lib$/, readdir $dir;
closedir $dir;
die "Unable to find the apr lib" unless ($aprutil_libname = $libs[0]);

my %apu_args = (APRUTIL_MAJOR_VERSION => $vers{MAJOR},
                APRUTIL_DOTTED_VERSION => $dotted,
                APRUTIL_LIBNAME => $aprutil_libname,
                prefix => $prefix,
                exec_prefix => $prefix,
                bindir => $ap_dir{bin},
                libdir => $ap_dir{lib},
                datadir => $prefix,
                installbuilddir => $ap_dir{build},
                includedir => $ap_dir{include},
                
                CC => $Config{cc},
                CPP => $Config{cpp},
                LD => $Config{ld},
                SHELL => $ENV{comspec},
                CPPFLAGS => '',
                CFLAGS => q{ /nologo /MD /W3 /O2 /D WIN32 /D _WINDOWS /D NDEBUG },
                LDFLAGS => q{ kernel32.lib /nologo /subsystem:windows /dll },
                LIBS => '',
                EXTRA_INCLUDES => '',
                APRUTIL_SOURCE_DIR => '',
                APRUTIL_SO_EXT => $Config{dlext},
                APRUTIL_LIB_TARGET => '',
               );

my $apu_usage = << "EOF";
Usage: apu-$vers{MAJOR}-config [OPTION]

Known values for OPTION are:
  --prefix[=DIR]    change prefix to DIR
  --bindir          print location where binaries are installed
  --includedir      print location where headers are installed
  --libdir          print location where libraries are installed
  --cc              print C compiler name
  --cpp             print C preprocessor name and any required options
  --ld              print C linker name
  --cflags          print C compiler flags
  --cppflags        print cpp flags
  --includes        print include information
  --ldflags         print linker flags
  --libs            print additional libraries to link against
  --srcdir          print APR-util source directory
  --installbuilddir print APR-util build helper directory
  --link-ld         print link switch(es) for linking to APR-util
  --apu-so-ext      print the extensions of shared objects on this platform
  --apu-lib-file    print the name of the aprutil lib
  --version         print the APR-util version as a dotted triple
  --help            print this help

When linking, an application should do something like:
  APU_LIBS="\`apu-config --link-ld --libs\`"

An application should use the results of --cflags, --cppflags, --includes,
and --ldflags in their build process.
EOF

my $full = catfile $ap_dir{bin}, $file;
open(my $fh, '>', $full) or die "Cannot open $full: $!";
print $fh <<"END";
#!$^X
use strict;
use warnings;
use Getopt::Long;
use File::Spec::Functions qw(catfile catdir);

$license
sub usage {
    print << 'EOU';
$apu_usage
EOU
    exit(1);
}

END

foreach my $var (keys %apu_args) {
    print $fh qq{my \${$var} = q[$apu_args{$var}];\n};
}
print $fh $_ while <DATA>;
close $fh;

my @args = ('pl2bat', $full);
system(@args) == 0 or die "system @args failed: $?";
print qq{$file.bat has been created under $ap_dir{bin}.\n\n};

__DATA__

my %opts = ();
GetOptions(\%opts,
           'prefix:s',
           'bindir',
           'includedir',
           'libdir',
           'cc',
           'cpp',
           'ld',
           'cflags',
           'cppflags',
           'includes',
           'ldflags',
           'libs',
           'srcdir',
           'installbuilddir',
           'link-ld',
           'apu-so-ext',
           'apu-lib-file',
           'version',
           'help'
          ) or usage();

usage() if ($opts{help} or not %opts);

if (exists $opts{prefix} and $opts{prefix} eq "") {
    print qq{$prefix\n};
    exit(0);
}
my $user_prefix = defined $opts{prefix} ? $opts{prefix} : '';
my %user_dir;
if ($user_prefix) {
    foreach (qw(lib bin include build)) {
        $user_dir{$_} = catdir $user_prefix, $_;
    }
}

my $flags = '';

SWITCH : {
    local $\ = "\n";
    $opts{bindir} and do {
        print $user_prefix ? $user_dir{bin} : $bindir;
        last SWITCH;
    };
    $opts{includedir} and do {
        print $user_prefix ? $user_dir{include} : $includedir;
        last SWITCH;
    };
    $opts{libdir} and do {
        print $user_prefix ? $user_dir{lib} : $libdir;
        last SWITCH;
    };
    $opts{installbuilddir} and do {
        print $user_prefix ? $user_dir{build} : $installbuilddir;
        last SWITCH;
    };
    $opts{srcdir} and do {
        print $APRUTIL_SOURCE_DIR;
        last SWITCH;
    };
    $opts{cc} and do {
        print $CC;
        last SWITCH;
    };
    $opts{cpp} and do {
        print $CPP;
        last SWITCH;
    };
    $opts{ld} and do {
        print $LD;
        last SWITCH;
    };
    $opts{cflags} and $flags .= " $CFLAGS ";
    $opts{cppflags} and $flags .= " $CPPFLAGS ";
    $opts{includes} and do {
        my $inc = $user_prefix ? $user_dir{include} : $includedir;
        $flags .= qq{ /I"$inc" $EXTRA_INCLUDES };
    };
    $opts{ldflags} and $flags .= " $LDFLAGS ";
    $opts{libs} and $flags .= " $LIBS ";
    $opts{'link-ld'} and do {
        my $libpath = $user_prefix ? $user_dir{lib} : $libdir;
        $flags .= qq{ /libpath:"$libpath" $APRUTIL_LIBNAME };
    };
    $opts{'apu-so-ext'} and do {
        print $APRUTIL_SO_EXT;
        last SWITCH;
    };
    $opts{'apu-lib-file'} and do {
        my $full_apulib = $user_prefix ? 
            (catfile $user_dir{lib}, $APRUTIL_LIBNAME) :
                (catfile $libdir, $APRUTIL_LIBNAME);
        print $full_apulib;
        last SWITCH;
    };
    $opts{version} and do {
        print $APRUTIL_DOTTED_VERSION;
        last SWITCH;
    };
    print $flags if $flags;
}
exit(0);
