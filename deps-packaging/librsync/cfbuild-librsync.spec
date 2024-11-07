# This RPM supposes that you download the release tar.gz file from github to SOURCES directory as v2.3.4.tar.gz

%define name librsync
%define version 2.3.4
%define gitsource https://github.com/librsync/%{name}/archive/v%{version}.tar.gz

Summary:  	CFEngine Build Automation - Rsync libraries
Name:     	cfbuild-librsync
Version:  	%{version}
Release:  	1%{?dist}
License:	LGPL
Group:    	System Environment/Libraries
Source0:	%{name}-%{version}.tar.gz
URL:       	http://librsync.sourcefrog.net
BuildRoot:	%{_topdir}/BUILD/%{name}-%{version}-%{release}-buildroot

AutoReqProv: no

%define prefix %{buildprefix}

%description
librsync implements the "rsync" algorithm, which allows remote
differencing of binary files.  librsync computes a delta relative to a
file's checksum, so the two files need not both be present to generate
a delta.

%package devel
Summary: Headers and development libraries for librsync
Group: Development/Libraries
Requires: %{name} = %{version}

%description devel
librsync implements the "rsync" algorithm, which allows remote
differencing of binary files.  librsync computes a delta relative to a
file's checksum, so the two files need not both be present to generate
a delta.

This package contains header files necessary for developing programs
based on librsync.

%prep
#wget --no-check-certificate --timeout=5 -O %{_sourcedir}/v%{version}.tar.gz %{gitsource}
mkdir -p %{_builddir}
cmake -DCMAKE_INSTALL_PREFIX=%{prefix} -DCMAKE_BUILD_TYPE=Release .
%setup -q -n %{name}-%{version}

# The next line is only needed if there are any non-upstream patches.  In
# this distribution there are none.
#%patch

%build
make

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%doc AUTHORS COPYING NEWS.md README.md
%{_bindir}/rdiff
%{_mandir}/man1/rdiff.1.gz
%{_libdir}/%{name}*
%{_mandir}/man3/librsync.3.gz

%files devel
%defattr(-,root,root)
%{_includedir}/%{name}*

%changelog
