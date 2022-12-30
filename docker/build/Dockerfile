FROM rxv-build-quartus:latest
MAINTAINER Jamie Iles <jamie@jamieiles.com>
ENV DEBIAN_FRONTEND=noninteractive
ARG VERILATOR_VERSION=5.004
RUN apt-get update && apt-get install --no-install-recommends -y \
	autoconf \
        bison \
	build-essential \
        ccache \
        clang \
        clang-c++ \
        cmake \
        cpp \
        curl \
	device-tree-compiler \
	flatbuffers-compiler \
        flex \
	gawk \
        git \
	gperf \
	graphviz \
	libboost-program-options-dev \
        libboost-python1.74.0 \
        libboost-python-dev \
        libboost-serialization-dev \
	libclang-dev \
	libffi-dev \
	libflatbuffers1 \
	libflatbuffers-dev \
        libfl-dev \
	libfmt-dev \
	libfmt-dev \
	libftdi-dev \
	libgmp-dev \
	libreadline-dev \
        libsdl2-2.0-0 \
        libsdl2-dev \
        libusb-1.0-0-dev \
        llvm \
	llvm-12-dev \
	mercurial \
        ninja-build \
	pkg-config \
	python3 \
	python3-click \
        python3-dev \
        python3-distorm3 \
        python3-lxml \
        python3-pip \
        python3-pystache \
        python3-pystache \
        python3-yaml \
        python3-yaml \
        ruby \
        ruby-dev \
	tcl-dev \
	unzip \
        wget \
	xdot \
	xxd \
	zip
RUN cd /tmp && \
	wget https://github.com/verilator/verilator/archive/refs/tags/v$VERILATOR_VERSION.tar.gz && \
        tar xf v$VERILATOR_VERSION.tar.gz && \
        cd verilator-$VERILATOR_VERSION && \
	autoconf && \
        ./configure --prefix=/usr && \
        make -j$(nproc) && \
        make install && \
        cd /tmp && \
        rm verilator-$VERILATOR_VERSION -rf
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
RUN cd /tmp && \
	wget https://github.com/zachjs/sv2v/releases/download/v0.0.9/sv2v-Linux.zip && \
	unzip sv2v-Linux.zip && \
	cp sv2v-Linux/sv2v /usr/bin && \
	rm sv2v-Linux *.zip -r

RUN mkdir -p /build
WORKDIR /build
RUN rm /usr/bin/gcov; ln -s /usr/bin/llvm-cov /usr/bin/gcov
