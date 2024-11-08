%define librsync_version 2.3.4

Summary: CFEngine Build Automation -- librsync
Name: cfbuild-librsync
Version: %{version}
Release: 1
Source0: librsync-%{librsync_version}.tar.gz
License: LGPL
Group: Other
Url: http://librsync.sourcefrog.net
BuildRoot: %{_topdir}/BUILD/%{name}-%{version}-%{release}-buildroot

AutoReqProv: no

%define prefix %{buildprefix}

%prep
mkdir -p %{_builddir}
%setup -q -n librsync-%{librsync_version}
for i in %{_topdir}/SOURCES/00*.patch; do
    $PATCH -p1 < $i
done

# Touch this file, or else autoreconf is called for some reason
touch config.hin
touch aclocal.m4
./configure --prefix=%{prefix}

%build

make

%install
rm -rf ${RPM_BUILD_ROOT}

make install DESTDIR=${RPM_BUILD_ROOT}

rm -rf ${RPM_BUILD_ROOT}%{prefix}/lib/*.a
rm -rf ${RPM_BUILD_ROOT}%{prefix}/lib/*.la

%clean
rm -rf $RPM_BUILD_ROOT

%package devel
Summary: CFEngine Build Automation -- librsync -- development files
Group: Other
AutoReqProv: no

%description
CFEngine Build Automation -- librsync

%description devel
CFEngine Build Automation -- librsync -- development files

%files
%defattr(-,root,root)

%dir %prefix/lib
%prefix/lib/*.so.*
%prefix/lib/*.so

%files devel
%defattr(-,root,root)

%prefix/include

%dir %prefix/lib
%prefix/lib/*.so

%changelog
