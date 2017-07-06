# now start phase 2
FROM scratch
LABEL maintianer Chen, Wenli <chenwenli@chenwenli.com>

COPY --from=tim03/lfs-tools /lfs /

ENV \
	PATH=/bin:/usr/bin:/sbin:/usr/sbin:/tools/bin  

COPY passwd /etc/passwd
COPY group /etc/group
USER root

COPY FHS.sh .
RUN ["/tools/bin/bash", "-c", "./FHS.sh"]

RUN ["/tools/bin/bash", "-c", " \
ln -sv /tools/bin/{bash,cat,echo,pwd,stty} /bin && \
ln -sv /tools/bin/perl /usr/bin && \
ln -sv /tools/lib/libgcc_s.so{,.1} /usr/lib && \
ln -sv /tools/lib/libstdc++.so{,.6} /usr/lib && \
sed 's/tools/usr/' /tools/lib/libstdc++.la > /usr/lib/libstdc++.la && \
ln -sv bash /bin/sh \
"]
RUN \
	touch /var/log/{btmp,lastlog,faillog,wtmp} && \
	chgrp -v utmp /var/log/lastlog && \
	chmod -v 664  /var/log/lastlog && \
	chmod -v 600  /var/log/btmp

WORKDIR /sources
# 6.7.1 Installation of Linux API Headers 
RUN \
	tar xvf linux-4.9.9.tar.xz && \
	mv -v linux-4.9.9 linux && \
	pushd linux && \
	make mrproper && \
	make INSTALL_HDR_PATH=dest headers_install && \
	find dest/include \( -name .install -o -name ..install.cmd \) -delete && \
	cp -rv dest/include/* /usr/include && \
	popd && \
	rm -rf linux

# 6.9 Glibc
RUN \
	tar xvf glibc-2.25.tar.xz && \
	mv -v glibc-2.25 glibc && \
	cd glibc && \
	patch -Np1 -i ../glibc-2.25-fhs-1.patch && \
	case $(uname -m) in \
    		x86) ln -s ld-linux.so.2 /lib/ld-lsb.so.3 \
    		;; \
    		x86_64) ln -s ../lib/ld-linux-x86-64.so.2 /lib64 && \
    		        ln -s ../lib/ld-linux-x86-64.so.2 /lib64/ld-lsb-x86-64.so.3 \
    		;; \
	esac  && \
	mkdir -v build && \
	cd build && \
	../configure                          \
   	   --prefix=/usr		\
   	   --enable-kernel=2.6.32             \
             --enable-obsolete-rpc           \
             --enable-stack-protector=strong \
             libc_cv_slibdir=/lib && \
    	make -j"$(nproc)"  && \
	make check || true && \
	touch /etc/ld.so.conf && \
	make install && \
	cp -v ../nscd/nscd.conf /etc/nscd.conf && \
	mkdir -pv /var/cache/nscd && \
	mkdir -pv /usr/lib/locale && \
	localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8 && \
	localedef -i de_DE -f ISO-8859-1 de_DE && \
	localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro && \
	localedef -i de_DE -f UTF-8 de_DE.UTF-8 && \
	localedef -i en_GB -f UTF-8 en_GB.UTF-8 && \
	localedef -i en_HK -f ISO-8859-1 en_HK && \
	localedef -i en_PH -f ISO-8859-1 en_PH && \
	localedef -i en_US -f ISO-8859-1 en_US && \
	localedef -i en_US -f UTF-8 en_US.UTF-8 && \
	localedef -i es_MX -f ISO-8859-1 es_MX && \
	localedef -i fa_IR -f UTF-8 fa_IR && \
	localedef -i fr_FR -f ISO-8859-1 fr_FR && \
	localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro && \
	localedef -i fr_FR -f UTF-8 fr_FR.UTF-8 && \
	localedef -i it_IT -f ISO-8859-1 it_IT && \
	localedef -i it_IT -f UTF-8 it_IT.UTF-8 && \
	localedef -i ja_JP -f EUC-JP ja_JP && \
	localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R && \
	localedef -i ru_RU -f UTF-8 ru_RU.UTF-8 && \
	localedef -i tr_TR -f UTF-8 tr_TR.UTF-8 && \
	localedef -i zh_CN -f GB18030 zh_CN.GB18030  && \
	cd $LFS/sources && \
	rm -rf glibc

COPY nsswitch.conf /etc
ARG ZONEINFO=/usr/share/zoneinfo
RUN \
	mkdir -v tzdata && cd tzdata && \
	tar -xf ../tzdata2016j.tar.gz && \
	mkdir -pv $ZONEINFO/{posix,right} && \
	for tz in etcetera southamerica northamerica europe africa antarctica  \
	          asia australasia backward pacificnew systemv; do \
	    zic -L /dev/null   -d $ZONEINFO       -y "sh yearistype.sh" ${tz} && \
	    zic -L /dev/null   -d $ZONEINFO/posix -y "sh yearistype.sh" ${tz} && \
	    zic -L leapseconds -d $ZONEINFO/right -y "sh yearistype.sh" ${tz}; \
	done && \
	cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO && \
	zic -d $ZONEINFO -p America/New_York && \
	cd .. && rm -rf tzdata

RUN ln -sfv /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 
COPY ld.so.conf /etc
RUN mkdir -pv /etc/ld.so.conf.d

# 6.10. Adjusting the Toolchain 
RUN \
	mv -v /tools/bin/{ld,ld-old} && \
	mv -v /tools/$(uname -m)-pc-linux-gnu/bin/{ld,ld-old} && \
	mv -v /tools/bin/{ld-new,ld} && \
	ln -sv /tools/bin/ld /tools/$(uname -m)-pc-linux-gnu/bin/ld  && \
	gcc -dumpspecs | sed -e 's@/tools@@g'                   \
    		-e '/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}' \
    		-e '/\*cpp:/{n;s@$@ -isystem /usr/include@}' >      \
    		`dirname $(gcc --print-libgcc-file-name)`/specs

# 6.11 Zlib
RUN \
	tar xvf zlib-1.2.11.tar.xz && \
	mv -v zlib-1.2.11 zlib && \
	cd zlib && \
	./configure --prefix=/usr && \
	make -j"$(nproc)" && \
	make check && \
	make install && \
	mv -v /usr/lib/libz.so.* /lib && \
	ln -sfv ../../lib/$(readlink /usr/lib/libz.so) /usr/lib/libz.so  && \
	cd $LFS/sources && \
	rm -rf xz

# 6.12 File
RUN \
	tar xvf file-5.30.tar.gz && \
	mv -v file-5.30 file && \
	cd file && \
	./configure --prefix=/tools && \
	make -j"$(nproc)" && \
	make check && \
	make install && \
	cd $LFS/sources && \
	rm -rf file


# 6.13 Binutils
RUN \
	tar xjvf binutils-2.27.tar.bz2 && \
	mv -v binutils-2.27 binutils && \
	cd binutils && \
	mkdir -v build && \
	cd build && \
	../configure 	--prefix=/usr \
	             --enable-gold       \
             --enable-ld=default \
             --enable-plugins    \
             --enable-shared     \
             --disable-werror    \
             --with-system-zlib && \
	make -j"$(nproc)" tooldir=/usr && \
	make -k check || true && \
	make tooldir=/usr install && \
	cd $LFS/sources && \
	rm -rf binutils

# 6.14 GMP
RUN \
	tar xvf gmp-6.1.2.tar.xz && \
	mv -v gmp-6.1.2 gmp && \
	cd gmp && \
	./configure 	--prefix=/usr \
            --enable-cxx     \
            --disable-static \
            --docdir=/usr/share/doc/gmp-6.1.2 && \
	make -j"$(nproc)" && \
	make check 2>&1 | tee gmp-check-log && \
	awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log && \
	make install && \
	cd $LFS/sources && \
	rm -rf gmp

# 6.15 MPFR
RUN \
	tar xvf mpfr-3.1.5.tar.xz && \
	mv -v mpfr-3.1.5 mpfr && \
	cd mpfr && \
	./configure --prefix=/usr        \
            --disable-static     \
            --enable-thread-safe \
            --docdir=/usr/share/doc/mpfr-3.1.5 && \
	make && \
	make check && \
	make install && \
	cd $LFS/sources && \
	rm -rf mpfr

# 6.16 MPC
RUN \
	tar xvf mpc-1.0.3.tar.gz && \
	mv -v mpc-1.0.3 mpc && \
	cd mpc && \
	./configure --prefix=/usr        \
            --disable-static     \
            --enable-thread-safe \
            --docdir=/usr/share/doc/mpfr-3.1.5 && \
	make && \
	make check && \
	make install && \
	cd $LFS/sources && \
	rm -rf mpc

# 6.17 GCC
RUN \
	tar xjf gcc-6.3.0.tar.bz2 && \
	mv -v gcc-6.3.0 gcc && \
	cd gcc && \
	case $(uname -m) in \
  	x86_64) \
    		sed -e '/m64=/s/lib64/lib/' \
        	    -i.orig gcc/config/i386/t-linux64 \
  	;; \
	esac && \
	mkdir -v build && \
	cd build && \
	SED=sed \
	../configure                                       \
	    --prefix=/usr				   \
	    --disable-multilib                             \
	    --disable-bootstrap                            \
	    --with-system-zlib				   \
	    --enable-languages=c,c++			&& \
	make -j"$(nproc)"  && \
	ulimit -s 32768 && \
	make -k check || true && \
	../contrib/test_summary | grep -A7 Summ && \
	make install && \
	ln -sv ../usr/bin/cpp /lib && \
	ln -sfv gcc /tools/bin/cc && \
	install -v -dm755 /usr/lib/bfd-plugins && \
	ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/6.3.0/liblto_plugin.so \
        /usr/lib/bfd-plugins/ && \
	cd $LFS/sources && \
	rm -rf gcc


# 6.18. Bzip2
RUN \
        tar xvf bzip2-1.0.6.tar.gz && \
        mv -v bzip2-1.0.6 bzip2 && \
        cd bzip2 && \
        patch -p1 < ../bzip2-1.0.6-install_docs-1.patch  && \
	sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile && \
	sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile && \
	make -f Makefile-libbz2_so -j"$(nproc)" && \
	make clean && \
        make -j"$(nproc)" && make PREFIX=/usr install && \
	cp -v bzip2-shared /bin/bzip2 && \
	cp -av libbz2.so* /lib && \
	ln -sv ../../lib/libbz2.so.1.0 /usr/lib/libbz2.so && \
	rm -v /usr/bin/{bunzip2,bzcat,bzip2} && \
	ln -sv bzip2 /bin/bunzip2 && \
	ln -sv bzip2 /bin/bzcat && \
        cd $LFS/sources && \
        rm -rf bzip2

# 6.19. Pkg-config
RUN \
	tar xvf pkg-config-0.29.1.tar.gz && \
	mv -v pkg-config-0.29.1 pkg-config && \
	cd pkg-config && \
	./configure --prefix=/usr              \
            --with-internal-glib       \
            --disable-compile-warnings \
            --disable-host-tool        \
            --docdir=/usr/share/doc/pkg-config-0.29.1 && \
	make -j"$(nproc)" && \
	make check && \
	make install && \
	cd $LFS/sources && \
	rm -rf pkg-config

# 6.20. Ncurses
RUN \
	tar xvf ncurses-6.0.tar.gz && \
	mv -v ncurses-6.0 ncurses && \
	cd ncurses && \
	sed -i '/LIBTOOL_INSTALL/d' c++/Makefile.in && \
	./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --enable-pc-files       \
            --enable-widec	&&  \
	make -j"$(nproc)" && \
	make install && \
	mv -v /usr/lib/libncursesw.so.6* /lib && \
	ln -sfv ../../lib/$(readlink /usr/lib/libncursesw.so) /usr/lib/libncursesw.so && \
	for lib in ncurses form panel menu ; do \
    		rm -vf                    /usr/lib/lib${lib}.so && \
    		echo "INPUT(-l${lib}w)" > /usr/lib/lib${lib}.so && \
    		ln -sfv ${lib}w.pc        /usr/lib/pkgconfig/${lib}.pc; \
	done && \
	rm -vf                     /usr/lib/libcursesw.so && \
	echo "INPUT(-lncursesw)" > /usr/lib/libcursesw.so && \
	ln -sfv libncurses.so      /usr/lib/libcurses.so  && \
	cd $LFS/sources && \
	rm -rf ncurses

# 6.21. Attr
RUN \
	tar xvf attr-2.4.47.src.tar.gz && \
	mv -v attr-2.4.47 attr && \
	cd attr && \
	sed -i -e 's|/@pkg_name@|&-@pkg_version@|' include/builddefs.in && \
	sed -i -e "/SUBDIRS/s|man[25]||g" man/Makefile && \
	./configure --prefix=/usr \
            --disable-static 	&& \
	make -j"$(nproc)" && \
	(make -j1 tests root-tests || true) && \
	make install install-dev install-lib && \
	chmod -v 755 /usr/lib/libattr.so && \
	mv -v /usr/lib/libattr.so.* /lib && \
	ln -sfv ../../lib/$(readlink /usr/lib/libattr.so) /usr/lib/libattr.so && \
	cd $LFS/sources && \
	rm -rf attr

# 6.22. Acl
RUN \
	tar xvf acl-2.2.52.src.tar.gz && \
	mv -v acl-2.2.52 acl && \
	cd acl && \
	sed -i -e 's|/@pkg_name@|&-@pkg_version@|' include/builddefs.in && \
	sed -i "s:| sed.*::g" test/{sbits-restore,cp,misc}.test && \
	sed -i -e "/TABS-1;/a if (x > (TABS-1)) x = (TABS-1);" \
    		libacl/__acl_to_any_text.c && \
	./configure --prefix=/usr    \
            --disable-static \
            --libexecdir=/usr/lib   && \
	make -j"$(nproc)" && \
	make install install-dev install-lib && \
	chmod -v 755 /usr/lib/libacl.so && \
	mv -v /usr/lib/libacl.so.* /lib && \
	ln -sfv ../../lib/$(readlink /usr/lib/libacl.so) /usr/lib/libacl.so  && \
	cd $LFS/sources && \
	rm -rf acl

# 6.23. Libcap
RUN \
	tar xvf libcap-2.25.tar.xz && \
	mv -v libcap-2.25 libcap && \
	cd libcap && \
	sed -i '/install.*STALIBNAME/d' libcap/Makefile && \
	make -j"$(nproc)" && \
	make RAISE_SETFCAP=no lib=lib prefix=/usr install && \
	chmod -v 755 /usr/lib/libcap.so && \
	mv -v /usr/lib/libcap.so.* /lib && \
	ln -sfv ../../lib/$(readlink /usr/lib/libcap.so) /usr/lib/libcap.so  && \
	cd $LFS/sources && \
	rm -rf libcap

# 6.24 sed
RUN \
	tar xvf sed-4.4.tar.xz && \
	mv -v sed-4.4 sed && \
	cd sed && \
	sed -i 's/usr/tools/'       build-aux/help2man && \
	sed -i 's/panic-tests.sh//' Makefile.in && \
	./configure --prefix=/usr --bindir=/bin && \
	make -j"$(nproc)" && \
	(make check || true) && \
	make install && \
	cd $LFS/sources && \
	rm -rf sed

# 6.25 Shadow
COPY useradd.c.patch .
RUN \
	tar xvf shadow-4.4.tar.xz && \
	mv -v shadow-4.4 shadow && \
	cd shadow && \
	sed -i 's/groups$(EXEEXT) //' src/Makefile.in && \
	find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \; && \
	find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \; && \
	find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;  && \
	sed -i -e 's@#ENCRYPT_METHOD DES@ENCRYPT_METHOD SHA512@' \
       		-e 's@/var/spool/mail@/var/mail@' etc/login.defs && \
	cat ../useradd.c.patch | patch -p0 -l && \
	sed -i 's/1000/999/' etc/useradd && \
	sed -i -e '47 d' -e '60,65 d' libmisc/myname.c && \
	./configure --sysconfdir=/etc --with-group-name-max-length=32 && \
	make -j"$(nproc)" && \
	make install && \
	mv -v /usr/bin/passwd /bin && \
	pwconv && \
	grpconv && \
	cd $LFS/sources && \
	rm -rf shadow

# 6.26. Psmisc
RUN \
	tar xvf psmisc-22.21.tar.gz && \
	mv -v psmisc-22.21 psmisc && \
	cd psmisc && \
	./configure --prefix=/usr && \
	make -j"$(nproc)" && \
	make install && \
	mv -v /usr/bin/fuser   /bin && \
	mv -v /usr/bin/killall /bin && \
	cd $LFS/sources && \
	rm -rf psmisc

# 6.27. Iana-Etc
RUN \
	tar xvf iana-etc-2.30.tar.bz2 && \
	mv -v iana-etc-2.30 iana-etc && \
	cd iana-etc && \
	make -j"$(nproc)" && \
	make install && \
	cd $LFS/sources && \
	rm -rf iana-etc

# 6.28 M4
RUN \
	tar xvf m4-1.4.18.tar.xz && \
	mv -v m4-1.4.18 m4 && \
	cd m4 && \
	./configure --prefix=/usr && \
	make -j"$(nproc)" && make install && \
	cd $LFS/sources && \
	rm -rf m4

# 6.29. Bison
RUN \
	tar xvf bison-3.0.4.tar.xz && \
	mv -v bison-3.0.4 bison && \
	cd bison && \
	./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.0.4 && \
	make -j"$(nproc)" && make install && \
	cd $LFS/sources && \
	rm -rf bison
	
# 6.30. Flex
RUN \
	tar xvf flex-2.6.3.tar.gz && \
	mv -v flex-2.6.3 flex && \
	cd flex && \
	HELP2MAN=/tools/bin/true \
	./configure --prefix=/usr --docdir=/usr/share/doc/flex-2.6.3 && \
	make -j"$(nproc)" && \
	make check || true && \
	make install && \
	ln -sv flex /usr/bin/lex && \
	cd $LFS/sources && \
	rm -rf flex

# 6.31. Grep
RUN \
	tar xvf grep-3.0.tar.xz && \
	mv -v grep-3.0 grep && \
	cd grep && \
	./configure --prefix=/usr --bindir=/bin && \
	make -j"$(nproc)" && \
	make check && \
	make install && \
	cd $LFS/sources && \
	rm -rf grep
	
# 6.32. Readline
RUN \
	tar xvf readline-7.0.tar.gz && \
	mv -v readline-7.0 readline && \
	cd readline && \
	sed -i '/MV.*old/d' Makefile.in && \
	sed -i '/{OLDSUFF}/c:' support/shlib-install  && \
	./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/readline-7.0  && \
	make SHLIB_LIBS=-lncurses -j"$(nproc)" && \
	make SHLIB_LIBS=-lncurses install && \
	mv -v /usr/lib/lib{readline,history}.so.* /lib && \
	ln -sfv ../../lib/$(readlink /usr/lib/libreadline.so) /usr/lib/libreadline.so && \
	ln -sfv ../../lib/$(readlink /usr/lib/libhistory.so ) /usr/lib/libhistory.so  && \
	cd $LFS/sources && \
	rm -rf readline

# 6.33. Bash
RUN \
	tar xvf bash-4.4.tar.gz && \
	mv -v bash-4.4 bash && \
	cd bash && \
	patch -p1 < ../bash-4.4-upstream_fixes-1.patch && \
	./configure --prefix=/usr                       \
            --docdir=/usr/share/doc/bash-4.4 \
            --without-bash-malloc               \
            --with-installed-readline && \
	make -j"$(nproc)" && \
	chown -Rv nobody . && \
	su nobody -s /bin/bash -c "PATH=$PATH make tests" && \
	make install && \
	mv -vf /usr/bin/bash /bin && \
	ln -svf bash /tools/bin/sh && \
	cd $LFS/sources && \
	rm -rf bash

# 6.34. Bc
RUN \
	tar xvf bc-1.06.95.tar.bz2 && \
	mv -v bc-1.06.95 bc && \
	cd bc && \
	patch -p1 < ../bc-1.06.95-memory_leak-1.patch && \
	./configure --prefix=/usr           \
            --with-readline         \
            --mandir=/usr/share/man \
            --infodir=/usr/share/info && \
	make -j"$(nproc)" && \
	echo "quit" | ./bc/bc -l Test/checklib.b && \
	make install && \
	cd $LFS/sources && \
	rm -rf bc

# 6.35. Libtool
RUN \
	tar xvf libtool-2.4.6.tar.xz && \
	mv -v libtool-2.4.6 libtool && \
	cd libtool && \
	./configure --prefix=/usr && \
	make -j"$(nproc)" && \
	make check || true && \
	make install && \
	cd $LFS/sources && \
	rm -rf libtool

# 6.36. GDBM
RUN \
	tar xvf gdbm-1.12.tar.gz && \
	mv -v gdbm-1.12 gdbm && \
	cd gdbm && \
	./configure --prefix=/usr \
            --disable-static \
            --enable-libgdbm-compat && \
	make -j"$(nproc)" && \
	make check && \
	make install && \
	cd $LFS/sources && \
	rm -rf gdbm

# 6.37. Gperf
RUN \
	tar xvf gperf-3.0.4.tar.gz && \
	mv -v gperf-3.0.4 gperf && \
	cd gperf && \
	./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.0.4 && \
        make -j"$(nproc)" && \
        make -j1 check && \
        make install && \
	cd $LFS/sources && \
	rm -rf gperf

# 6.38. Expat
RUN \
	tar xvf expat-2.2.0.tar.bz2 && \
	mv -v expat-2.2.0 expat && \
	cd expat && \
	./configure --prefix=/usr --disable-static && \
        make -j"$(nproc)" && \
        make check && \
        make install && \
	cd $LFS/sources && \
	rm -rf expat 

# 6.39. Inetutils
RUN \
	echo "127.0.0.1 localhost $(hostname)" > /etc/hosts 
RUN \
	tar xvf inetutils-1.9.4.tar.xz && \
	mv -v inetutils-1.9.4 inetutils && \
	cd inetutils && \
	./configure --prefix=/usr        \
            --localstatedir=/var \
            --disable-logger     \
            --disable-whois      \
            --disable-rcp        \
            --disable-rexec      \
            --disable-rlogin     \
            --disable-rsh        \
            --disable-servers	&& \
        make -j"$(nproc)" && \
        (make check || true) && \
        make install && \
	mv -v /usr/bin/{hostname,ping,ping6,traceroute} /bin && \
	mv -v /usr/bin/ifconfig /sbin && \
	cd $LFS/sources && \
	rm -rf inetutils

# 6.40. Perl
RUN \
	tar xvf perl-5.24.1.tar.bz2 && \
	mv -v perl-5.24.1 perl && \
	cd perl && \
	export BUILD_ZLIB=False && \
	export BUILD_BZIP2=0 && \
	sh Configure -des -Dprefix=/usr \
			-Dvendorprefix=/usr \
			-Dpager="/usr/bin/less -isR" \
			-Duseshrplib && \
	make -j"$(nproc)" && \
	(make -k test || true) && \
	make install && \
	unset BUILD_ZLIB BUILD_BZIP2 && \
	cd $LFS/sources && \
	rm -rf perl

# 6.41. XML::Parser
RUN \
	tar xvf XML-Parser-2.44.tar.gz && \
	mv -v XML-Parser-2.44 XML-Parser && \
	cd XML-Parser && \
	perl Makefile.PL && \
	make -j"$(nproc)" && \
	make test && \
	make install && \
	cd $LFS/sources && \
	rm -rf XML-Parser

# 6.42. Intltool
RUN \
	tar xvf intltool-0.51.0.tar.gz && \
	mv -v intltool-0.51.0 intltool && \
	cd intltool && \
	sed -i 's:\\\${:\\\$\\{:' intltool-update.in && \
	./configure --prefix=/usr && \
	make -j"$(nproc)" && \
        make check && \
	make install && \
	cd $LFS/sources && \
        rm -rf inteltool

# 6.43. Autoconf
RUN \
	tar xvf autoconf-2.69.tar.xz && \
	mv -v autoconf-2.69 autoconf && \
	cd autoconf && \
	./configure --prefix=/usr && \
	make -j"$(nproc)" && \
	(make check || true) && \
	make install && \
	cd $LFS/sources && \
	rm -rf autoconf

# 6.44. Automake
RUN \
	tar xvf automake-1.15.tar.xz && \
	mv -v automake-1.15 automake && \
	cd automake && \
	sed -i 's:/\\\${:/\\\$\\{:' bin/automake.in && \
	./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.15 && \
	make -j"$(nproc)" && \
	sed -i "s:./configure:LEXLIB=/usr/lib/libfl.a &:" t/lex-{clean,depend}-cxx.sh && \
	(make -j4 check || true) && \
	make install && \
	cd $LFS/sources && \
	rm -rf automake

