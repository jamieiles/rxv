FROM rxv-build:latest
MAINTAINER Jamie Iles <jamie@jamieiles.com>
ARG USERNAME=devuser
ARG VERIBLE_VERSION=v0.0-4053-g89d4d98a
ARG VERIBLE_DISTRO=linux-static-x86_64
ARG UID=1000
RUN apt-get install -y gpg curl
RUN wget https://github.com/chipsalliance/verible/releases/download/$VERIBLE_VERSION/verible-$VERIBLE_VERSION-$VERIBLE_DISTRO.tar.gz && \
	tar xf verible-$VERIBLE_VERSION-$VERIBLE_DISTRO.tar.gz && \
	cp -r verible-$VERIBLE_VERSION/* /usr/ && \
	rm -r verible*
RUN echo "path-include=/usr/share/doc/fzf/examples/*" >> /etc/dpkg/dpkg.cfg.d/excludes
RUN apt-get update && apt-get install -y runit \
	autoconf \
	automake \
	build-essential \
	fzf \
	fzf \
	gdb \
	gtkwave \
	less \
	libbz2-dev \
	libgtk-3-dev \
	sudo \
	zsh
ADD docker/dev/rxv-dev /usr/bin/rxv-dev
ENV CTEST_OUTPUT_ON_FAILURE=1
ENV GTEST_COLOR=1
RUN deluser ubuntu
RUN useradd -u $UID -ms /bin/bash -G sudo,adm devuser
RUN echo "%sudo   ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
RUN mkdir -p /home/devuser/.vscode-server/extensions \
	/home/devuser/.vscode-server-insiders/extensions \
    && chown -R devuser \
	/home/devuser/.vscode-server \
	/home/devuser/.vscode-server-insiders
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
	&& mkdir /commandhistory \
	&& touch /commandhistory/.bash_history \
	&& chown -R $USERNAME /commandhistory \
	&& echo $SNIPPET >> "/home/$USERNAME/.bashrc"
RUN cd /tmp && \
	git clone https://github.com/gtkwave/gtkwave.git -b lts && \
	cd gtkwave/gtkwave3-gtk3/ && \
	./autogen.sh && \
	./configure --prefix=/usr --enable-gtk3 --disable-tcl && \
	make && \
	sudo make install && \
	cd /tmp && \
	rm -rf gtkwave
ENTRYPOINT ["/usr/bin/rxv-dev"]
