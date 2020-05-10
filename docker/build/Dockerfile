FROM ubuntu:20.04
MAINTAINER Jamie Iles <jamie@jamieiles.com>
ENV DEBIAN_FRONTEND=noninteractive
ARG VERILATOR_VERSION=4.034
RUN apt-get update && apt-get install --no-install-recommends -y \
	autoconf \
        bison \
	build-essential \
        ccache \
        clang \
        clang-c++ \
        cmake \
        cpp \
        flex \
	gawk \
        git \
	gperf \
	graphviz \
	libboost-program-options-dev \
        libboost-python1.71.0 \
        libboost-python-dev \
        libboost-serialization-dev \
	libffi-dev \
        libfl-dev \
	libftdi-dev \
	libgmp-dev \
	libreadline-dev \
        libsdl2-2.0-0 \
        libsdl2-dev \
        libusb-1.0-0-dev \
        llvm \
	mercurial \
        ninja-build \
	pkg-config \
	python \
	python3 \
        python3-pip \
        python3-pystache \
        python3-yaml \
        python-dev \
        python3-distorm3 \
        python-lxml \
        python3-pystache \
        python-yaml \
        ruby \
        ruby-dev \
	tcl-dev \
        wget \
	xdot
RUN cd /tmp && \
        wget https://www.veripool.org/ftp/verilator-$VERILATOR_VERSION.tgz && \
        tar xf verilator-$VERILATOR_VERSION.tgz && \
        cd verilator-$VERILATOR_VERSION && \
        ./configure --prefix=/usr && \
        make -j4 && \
        make install && \
        cd /tmp && \
        rm verilator* -rf
RUN cd /tmp && \
	git clone https://github.com/YosysHQ/yosys.git yosys && \
	cd yosys && \
	make -j$(nproc) && \
	make install && \
	cd /tmp && \
	rm -rf yosys
RUN cd /tmp && \
	git clone https://github.com/YosysHQ/SymbiYosys.git SymbiYosys && \
	cd SymbiYosys && \
	make install && \
	cd /tmp && \
	rm -rf SymbiYosys
RUN apt-get install -y curl
RUN git clone https://github.com/boolector/boolector && \
	cd boolector && \
	./contrib/setup-btor2tools.sh && \
	./contrib/setup-lingeling.sh && \
	./configure.sh && \
	make -C build -j$(nproc) && \
	cp build/bin/boolector /usr/bin/ && \
	cp build/bin/btor* /usr/bin/ && \
	cp deps/btor2tools/bin/btorsim /usr/bin/ && \
	cd / && \
	rm -rf boolector
RUN cd /tmp && \
	wget https://static.dev.sifive.com/dev-tools/riscv64-unknown-elf-gcc-8.3.0-2019.08.0-x86_64-linux-ubuntu14.tar.gz && \
	mkdir -p /opt/riscv && \
	tar -C /usr --strip-components=1 -xf riscv64-unknown-elf-gcc-8.3.0-2019.08.0-x86_64-linux-ubuntu14.tar.gz && \
	rm *.tar.gz

RUN mkdir -p /build
WORKDIR /build
RUN rm /usr/bin/gcov; ln -s /usr/bin/llvm-cov /usr/bin/gcov
