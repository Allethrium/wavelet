Wavelet - An Integrated Video Distribution System
=================================================

Wavelet is available for use under the SSPL

https://en.wikipedia.org/wiki/Server_Side_Public_License




Component Licenses Below:

UltraGrid - A High Definition Collaboratory
===========================================

   Copyright (c) 2005-2021 CESNET z.s.p.o.
   Copyright (c) 2013-2014 Fundació i2CAT, Internet I Innovació Digital a Catalunya
   Copyright (c) 2001-2004 University of Southern California 
   Copyright (c) 2003-2004 University of Glasgow
   Copyright (c) 2003 University of Sydney
   Copyright (c) 1993-2001 University College London
   Copyright (c) 1996 Internet Software Consortium
   Copyright (c) 1993 Regents of the University of California
   Copyright (c) 1993 Eric Young
   Copyright (c) 1992 Xerox Corporation
   Copyright (c) 1991-1992 RSA Data Security, Inc.
   Copyright (c) 1991 Massachusetts Institute of Technology
   Copyright (c) 1991-1998 Free Software Foundation, Inc.
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, is permitted provided that the following conditions
   are met:

   1. Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.

   3. All advertising materials mentioning features or use of this software
      must display the following acknowledgement:

        This product includes software developed by the University of 
        Southern California/Information Sciences Institute and by the 
        University of Glasgow. This product also includes software 
        developed by CESNET z.s.p.o.

   4. Neither the name of the University nor of the Institute may be used
      to endorse or promote products derived from this software without
      specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE AUTHORS AND CONTRIBUTORS "AS IS" AND
   ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
   PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE
   LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
   CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
   SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
   INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
   CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
   ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
   THE POSSIBILITY OF SUCH DAMAGE.

   This product includes software developed by the Computer Science Department
   at University College London and by the Computer Systems Engineering Group 
   at Lawrence Berkeley Laboratory. 

   This product uses the RSA Data Security, Inc. MD5 Message-Digest Algorithm.  
   This product includes software developed by the OpenSSL Project
     for use in the OpenSSL Toolkit. (http://www.openssl.org/)
   This product includes EmbeddableWebServer created by Forrest Heller.

External libraries
------------------

### SpeexDSP

Copyright 2002-2008 	Xiph.org Foundation
Copyright 2002-2008 	Jean-Marc Valin
Copyright 2005-2007	Analog Devices Inc.
Copyright 2005-2008	Commonwealth Scientific and Industrial Research 
                        Organisation (CSIRO)
Copyright 1993, 2002, 2006 David Rowe
Copyright 2003 		EpicGames
Copyright 1992-1994	Jutta Degener, Carsten Bormann

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

- Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

- Neither the name of the Xiph.org Foundation nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

### zfec

This package implements an “erasure code”, or “forward error correction code”.

You may use this package under the GNU General Public License, version 2 or, at
your option, any later version. You may use this package under the Transitive
Grace Period Public Licence, version 1.0 or, at your option, any later version.
(You may choose to use this package under the terms of either licence, at your
 option.) See the file COPYING.GPL for the terms of the GNU General Public
License, version 2. See the file COPYING.TGPPL.rst for the terms of the
Transitive Grace Period Public Licence, version 1.0.

The most widely known example of an erasure code is the RAID-5 algorithm which
makes it so that in the event of the loss of any one hard drive, the stored data
can be completely recovered. The algorithm in the zfec package has a similar
effect, but instead of recovering from the loss of only a single element, it can
be parameterized to choose in advance the number of elements whose loss it can
tolerate.

This package is largely based on the old “fec” library by Luigi Rizzo et al.,
which is a mature and optimized implementation of erasure coding. The zfec
package makes several changes from the original “fec” package, including
addition of the Python API, refactoring of the C API to support zero-copy
operation, a few clean-ups and optimizations of the core code itself, and
the addition of a command-line tool named “zfec”.