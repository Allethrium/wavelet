# ffmpeg-7.1.spec
# Self-contained RPM spec for FFmpeg 7.1.x — vendored, no SRPM dependency.
# Purpose: provide libavcodec + hardware accel backend for UltraGrid with NDI-SDK compatibility.
# Network transport, demuxers, players, and nonfree libs intentionally excluded.
#
# Project license: SSPI — upstream licenses honoured.
# Resulting binary license: LGPL-2.1-or-later (ffmpeg-free build, no GPL libraries)
# No --enable-gpl; no --enable-nonfree; no x264/x265/lame/twolame/rubberband/placebo.
#
# Optional features (OFF by default, enable with rpmbuild --with <name>):
#   --with placebo   libplacebo GPU filter (GPLv3)
#   --with amr       OpenCORE AMR NB/WB   (Apache 2.0)
#   --with codec2    Codec2 voice codec   (LGPLv2.1)
#
# Disable defaults with rpmbuild --without <name>:
#   --without vaapi
#   --without vdpau
#   --without vpx
#   --without opus
#   --without jxl
#   --without zimg
#   --without svtav1
#   --without vmaf

%global _hardened_build 1
%global debug_package %{nil}

# ON by default
%bcond_without  vaapi
%bcond_without  vdpau
%bcond_without  vpx
%bcond_without  vmaf
%bcond_without  opus
%bcond_without  jxl
%bcond_without  zimg
%bcond_without  svtav1
%bcond_without  openh264

# OFF by default
%bcond_with     placebo
%bcond_with     amr
%bcond_with     codec2

# ── Package metadata ──────────────────────────────────────────────────────────

Name:           ffmpeg
Version:        7.1.4
Release:        1%{?dist}
Summary:        FFmpeg multimedia libraries — codec backend for UltraGrid (LGPL build)
License:        LGPL-2.1-or-later
URL:            https://ffmpeg.org/
Source0:        https://ffmpeg.org/releases/%{name}-%{version}.tar.xz

# Cannot coexist with Fedora's own ffmpeg-free
Conflicts:      ffmpeg-free
Provides:       ffmpeg-bin = %{version}-%{release}

# ── Build dependencies ────────────────────────────────────────────────────────

# Codec and filter libs
BuildRequires:  nasm
BuildRequires:  yasm
BuildRequires:  pkgconfig
BuildRequires:  bzip2-devel
BuildRequires:  freetype-devel
BuildRequires:  fontconfig-devel
BuildRequires:  fribidi-devel
BuildRequires:  libass-devel
BuildRequires:  libjpeg-turbo-devel
BuildRequires:  libpng-devel
BuildRequires:  librsvg2-devel
BuildRequires:  libtheora-devel
BuildRequires:  libvorbis-devel
BuildRequires:  libwebp-devel
BuildRequires:  speex-devel
BuildRequires:  openjpeg2-devel
BuildRequires:  libaom-devel
BuildRequires:  zlib-devel
BuildRequires:  python3

# Hardware acceleration
BuildRequires:  libdrm-devel
BuildRequires:  libglvnd-devel
BuildRequires:  mesa-libGL-devel

# Conditional deps
%{?with_vaapi:BuildRequires:   libva-devel >= 0.31.0}
%{?with_vdpau:BuildRequires:   libvdpau-devel}
%{?with_vpx:BuildRequires:     libvpx-devel >= 1.4.0}
%{?with_opus:BuildRequires:    opus-devel >= 1.1.3}
%{?with_jxl:BuildRequires:     libjxl-devel}
%{?with_zimg:BuildRequires:    zimg-devel >= 2.7.0}
%{?with_svtav1:BuildRequires:  svt-av1-devel >= 0.9.0}
%{?with_vmaf:BuildRequires:    libvmaf-devel >= 1.5.2}
%{?with_placebo:BuildRequires: libplacebo-devel >= 4.192.0}
%{?with_amr:BuildRequires:     opencore-amr-devel vo-amrwbenc-devel}
%{?with_codec2:BuildRequires:  codec2-devel}
%{?with_openh264:BuildRequires: openh264-devel}

# ── Subpackages ───────────────────────────────────────────────────────────────

%package        libs
Summary:        FFmpeg shared libraries (LGPL build)
License:        LGPL-2.1-or-later

%description    libs
FFmpeg shared libraries (libavcodec, libavformat, libavutil, libswscale, etc.).
Pinned at 7.1.x for UltraGrid NDI ABI compatibility. LGPL-2.1-or-later build.

%package        devel
Summary:        Development files for FFmpeg
Requires:       %{name}-libs%{?_isa} = %{version}-%{release}

%description    devel
Headers and pkg-config files for building against FFmpeg 7.1.x libraries.

%description
FFmpeg multimedia framework, codec backend build for UltraGrid.
Pinned at 7.1.x. No network transport, player, or nonfree components included.
LGPL-2.1-or-later build compatible with MIT and proprietary SDKs.

# ── Prep ──────────────────────────────────────────────────────────────────────

%prep
%autosetup -n %{name}-%{version}

# ── Build ─────────────────────────────────────────────────────────────────────

%build
# Disable LTO to avoid shared library build issues with x86 assembly
export CFLAGS="%{optflags}"
export CFLAGS="${CFLAGS//-flto=auto/}"
export CFLAGS="${CFLAGS//-ffat-lto-objects/}"
export CFLAGS="${CFLAGS//-fno-lto/}"
export CFLAGS="${CFLAGS} -fPIC"
export CXXFLAGS="${CFLAGS}"
export FFLAGS="${CFLAGS}"
export FCFLAGS="${CFLAGS}"

./configure \
    --prefix=%{_prefix} \
    --bindir=%{_bindir} \
    --datadir=%{_datadir}/%{name} \
    --docdir=%{_docdir}/%{name} \
    --incdir=%{_includedir}/%{name} \
    --libdir=%{_libdir} \
    --mandir=%{_mandir} \
    --arch=%{_target_cpu} \
    --disable-debug \
    --disable-static \
    --enable-shared \
    --disable-ffplay \
    --disable-frei0r \
    --disable-x11grab \
    --disable-xv \
    --disable-gpl \
    --disable-nonfree \
    --enable-pthreads \
    --enable-bzlib \
    --enable-fontconfig \
    --enable-libaom \
    --enable-libass \
    --enable-libdrm \
    --enable-libfreetype \
    --enable-libfribidi \
    --enable-libopenjpeg \
    --enable-librsvg \
    --enable-libspeex \
    --enable-libtheora \
    --enable-libvorbis \
    --enable-libwebp \
    --enable-vulkan \
    --cc=gcc \
    --extra-cflags="$CFLAGS" \
    %{?with_vaapi:  --enable-vaapi}    %{!?with_vaapi:  --disable-vaapi}   \
    %{?with_vdpau:  --enable-vdpau}    %{!?with_vdpau:  --disable-vdpau}   \
    %{?with_vpx:    --enable-libvpx}   %{!?with_vpx:    --disable-libvpx}  \
    %{?with_opus:   --enable-libopus}  %{!?with_opus:   --disable-libopus} \
    %{?with_jxl:         --enable-libjxl}      \
    %{?with_zimg:        --enable-libzimg}      \
    %{?with_svtav1:      --enable-libsvtav1}    \
    %{?with_vmaf:        --enable-libvmaf}      \
    %{?with_placebo:     --enable-libplacebo}   \
    %{?with_amr: --enable-libopencore_amrnb --enable-libopencore_amrwb --enable-libvo_amrwbenc} \
    %{?with_codec2:      --enable-libcodec2}    \
    %{?with_openh264:    --enable-libopenh264}  \
    %{nil}

%make_build

# ── Install ───────────────────────────────────────────────────────────────────

%install
%make_install
find %{buildroot} -name "*.a" -delete

# ── File lists ────────────────────────────────────────────────────────────────

%files
%license COPYING.LGPLv2.1 COPYING.LGPLv3
%doc README.md MAINTAINERS
%{_bindir}/ffmpeg
%{_bindir}/ffprobe
%{_datadir}/%{name}/
%{_mandir}/man1/ffmpeg*.1*
%{_mandir}/man1/ffprobe*.1*

%files libs
%license COPYING.LGPLv2.1 COPYING.LGPLv3
%{_libdir}/libav*.so.*
%{_libdir}/libsw*.so.*

%files devel
%{_includedir}/%{name}/
%{_libdir}/libav*.so
%{_libdir}/libsw*.so
%{_libdir}/pkgconfig/lib*.pc
%{_mandir}/man3/libav*.3*
%{_mandir}/man3/libsw*.3*

%changelog
* Tue Jul 21 2026 Your Name <you@example.com> - 7.1.4-1
- Vendored spec pinned at FFmpeg 7.1.4 for UltraGrid/NDI ABI compatibility
- Stripped to codec/hwaccel surface only; no network, player, or nonfree libs
- LGPL-2.1-or-later build; --disable-gpl --disable-nonfree; no x264/x265/lame/twolame/rubberband/placebo