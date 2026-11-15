FROM debian:bookworm

USER root

RUN apt-get -o Acquire::http::No-Cache=true update -y \
    && (apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common rsync \
        || (apt-get -o Acquire::http::No-Cache=true update -y && apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common rsync)) \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl -k https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
    && curl -k -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - \
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    && apt-get -o Acquire::http::No-Cache=true update -y \
    && set -- \
        google-cloud-cli \
        docker-ce-cli \
        xdg-utils libxss1 \
        fonts-liberation \
        libappindicator3-1 \
        libpq-dev \
        openjfx \
        jq \
        golang \
        mplayer \
		zip \
		libgtk2.0-0 \
		libgtk-3-0 \
		libnotify-dev \
		libgconf-2-4 \
		libgbm-dev \
		libnss3 \
		libxss1 \
		libasound2 \
		libxtst6 \
		xauth \
		xvfb \
		# install Chinese fonts
		# this list was copied from https://github.com/jim3ma/docker-leanote
		fonts-arphic-bkai00mp \
		fonts-arphic-bsmi00lp \
		fonts-arphic-gbsn00lp \
		fonts-arphic-gkai00mp \
		fonts-arphic-ukai \
		fonts-arphic-uming \
		ttf-wqy-zenhei \
		ttf-wqy-microhei \
		xfonts-wqy \
        golang \
		libgbm1 \
        libsqlite3-dev \
		fonts-liberation \
		libappindicator3-1 \
		xdg-utils \
        python3-pip \
        sudo \
        libbluetooth-dev \
		tk-dev \
		uuid-dev \
        build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libbz2-dev liblzma-dev libexpat1-dev wget\
        kubectl\
        google-cloud-cli-gke-gcloud-auth-plugin \
    && (apt-get install -y "$@" || (apt-get -o Acquire::http::No-Cache=true update -y && apt-get install -y "$@")) \
    && apt-get install -y -f \
    && rm -rf /var/lib/apt/lists/*

RUN gke-gcloud-auth-plugin --version
ENV NVM_DIR=/usr/local/nvm
ARG NVM_VERSION=v0.40.3

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip awscliv2.zip
RUN ./aws/install

RUN mkdir -p "${NVM_DIR}" \
    && curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash

RUN for version in v10.20.1 v12.16.0 v14.21.3 v16.20.1 v18.16.1 v20.20.2 v22.23.2 v24.20.0; do \
        mkdir -p "${NVM_DIR}/versions/node/${version}"; \
        curl -k -fsSL "https://nodejs.org/dist/${version}/node-${version}-linux-x64.tar.xz" \
            | tar -xJ --strip-components=1 -C "${NVM_DIR}/versions/node/${version}"; \
    done

RUN bash -c 'source /usr/local/nvm/nvm.sh   && \
    nvm use v24.20.0 && \
    npm install -g doctoc urchin eclint dockerfile_lint && \
    npm install -g npm@10.2.4 && \
    nvm alias default v24.20.0 && \
    nvm use default'

# pnpm in a versioned prefix, installed once at build time. The package keeps
# the "#!/usr/bin/env node" shebang, so it always runs with the Node that the
# pipeline selected; nothing is installed per job and no npm global of a Node
# version is mutated.
ARG PNPM_VERSION=10.34.9
RUN set -eux; \
    node_bin="${NVM_DIR}/versions/node/v24.20.0/bin"; \
    PATH="${node_bin}:${PATH}" npm install --global --prefix "/opt/pnpm/${PNPM_VERSION}" "pnpm@${PNPM_VERSION}"; \
    head -n 1 "/opt/pnpm/${PNPM_VERSION}/bin/pnpm" | grep -q '^#!/usr/bin/env node'; \
    PATH="${node_bin}:${PATH}" "/opt/pnpm/${PNPM_VERSION}/bin/pnpm" --version

ENV YARN_VERSION 1.22.5

RUN set -ex \
  && curl -k -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --batch --import \
  && curl -k -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
  && curl -k -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
  && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && mkdir -p /opt \
  && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/ \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarn /usr/local/bin/yarn \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarnpkg /usr/local/bin/yarnpkg \
  && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz


# ensure local python is preferred over distribution python
ENV PATH /usr/local/bin:$PATH

# http://bugs.python.org/issue19846
# > At the moment, setting "LANG=C" on a Linux system *fundamentally breaks Python 3*, and that's not OK.
ENV LANG C.UTF-8

# runtime dependencies
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libbluetooth-dev \
		tk-dev \
		uuid-dev \
	; \
	rm -rf /var/lib/apt/lists/*

ENV GPG_KEY E3FF2839C048B25C084DEBE9B26995E310250568
ENV PYTHON_VERSION 3.8.13

RUN set -eux; \
	\
	wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz"; \
	wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc"; \
	GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$GPG_KEY"; \
	gpg --batch --verify python.tar.xz.asc python.tar.xz; \
	command -v gpgconf > /dev/null && gpgconf --kill all || :; \
	rm -rf "$GNUPGHOME" python.tar.xz.asc; \
	mkdir -p /usr/src/python; \
	tar --extract --directory /usr/src/python --strip-components=1 --file python.tar.xz; \
	rm python.tar.xz; \
	\
	cd /usr/src/python; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	./configure \
		--build="$gnuArch" \
		--enable-loadable-sqlite-extensions \
		--enable-optimizations \
		--enable-option-checking=fatal \
		--enable-shared \
		--with-system-expat \
		--without-ensurepip \
	; \
	nproc="$(nproc)"; \
	make -j "$nproc" \
	; \
	make install; \
	\
# enable GDB to load debugging data: https://github.com/docker-library/python/pull/701
	bin="$(readlink -ve /usr/local/bin/python3)"; \
	dir="$(dirname "$bin")"; \
	mkdir -p "/usr/share/gdb/auto-load/$dir"; \
	cp -vL Tools/gdb/libpython.py "/usr/share/gdb/auto-load/$bin-gdb.py"; \
	\
	cd /; \
	rm -rf /usr/src/python; \
	\
	find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests -o -name idle_test \) \) \
			-o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' -o -name 'libpython*.a' \) \) \
			-o \( -type f -a -name 'wininst-*.exe' \) \
		\) -exec rm -rf '{}' + \
	; \
	\
	ldconfig; \
	\
	python3 --version

# make some useful symlinks that are expected to exist ("/usr/local/bin/python" and friends)
RUN set -eux; \
	for src in idle3 pydoc3 python3 python3-config; do \
		dst="$(echo "$src" | tr -d 3)"; \
		[ -s "/usr/local/bin/$src" ]; \
		[ ! -e "/usr/local/bin/$dst" ]; \
		ln -svT "$src" "/usr/local/bin/$dst"; \
	done

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 22.0.4
# https://github.com/docker-library/python/issues/365
ENV PYTHON_SETUPTOOLS_VERSION 57.5.0
# https://github.com/pypa/get-pip
ENV PYTHON_GET_PIP_URL https://github.com/pypa/get-pip/raw/aeca83c7ba7f9cdfd681103c4dcbf0214f6d742e/public/get-pip.py
ENV PYTHON_GET_PIP_SHA256 d0b5909f3ab32dae9d115aa68a4b763529823ad5589c56af15cf816fca2773d6

RUN set -eux; \
	\
	wget -O get-pip.py "$PYTHON_GET_PIP_URL"; \
	echo "$PYTHON_GET_PIP_SHA256 *get-pip.py" | sha256sum -c -; \
	\
	export PYTHONDONTWRITEBYTECODE=1; \
	\
	python get-pip.py \
		--disable-pip-version-check \
		--no-cache-dir \
		--no-compile \
		"pip==$PYTHON_PIP_VERSION" \
		"setuptools==$PYTHON_SETUPTOOLS_VERSION" \
	; \
	rm -f get-pip.py; \
	\
	pip --version


# Python 3.13 side-by-side for the projects that ask for it. It is never the
# default: the 3.8.13 in /usr/local, its symlinks and the legacy pip3.8 CLIs
# keep the PATH they have today. The prefix carries its own shared libpython
# and an rpath, so no loader configuration, PATH entry or symlink outside /opt
# changes. PGO is not enabled: it only affects speed and would multiply the
# build time of a second interpreter.
ARG PYTHON313_VERSION=3.13.18
ARG PYTHON313_SHA256=abb0102e6d4ae027509bcb82327d9dd85515b44a3ba8ad538cfc5e9847029f68
ARG PYTHON313_PIP_VERSION=26.3

RUN set -eux; \
	prefix="/opt/python/${PYTHON313_VERSION}"; \
	wget -O python313.tar.xz "https://www.python.org/ftp/python/${PYTHON313_VERSION}/Python-${PYTHON313_VERSION}.tar.xz"; \
	echo "${PYTHON313_SHA256} *python313.tar.xz" | sha256sum -c -; \
	mkdir -p /usr/src/python313; \
	tar --extract --directory /usr/src/python313 --strip-components=1 --file python313.tar.xz; \
	rm python313.tar.xz; \
	cd /usr/src/python313; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	./configure \
		--build="$gnuArch" \
		--prefix="$prefix" \
		--enable-loadable-sqlite-extensions \
		--enable-option-checking=fatal \
		--enable-shared \
		--with-system-expat \
		LDFLAGS="-Wl,-rpath,${prefix}/lib -Wl,--enable-new-dtags" \
	; \
	make -j "$(nproc)"; \
	make install; \
	cd /; \
	rm -rf /usr/src/python313; \
	ln -sf python3 "$prefix/bin/python"; \
	ln -sf pip3 "$prefix/bin/pip"; \
	"$prefix/bin/python3" -m pip install --no-cache-dir --disable-pip-version-check "pip==${PYTHON313_PIP_VERSION}"; \
	[ "$("$prefix/bin/python3" -c 'import sys; print(sys.prefix)')" = "$prefix" ]; \
	[ "$("$prefix/bin/python3" -c 'import sys; print(sys.base_prefix)')" = "$prefix" ]; \
	"$prefix/bin/python3" -c 'import bz2, lzma, sqlite3, ssl, sys, venv; print(sys.version.split()[0], ssl.OPENSSL_VERSION)'; \
	"$prefix/bin/python3" -m venv /tmp/python313-venv; \
	/tmp/python313-venv/bin/python -c 'import sys; assert sys.prefix != sys.base_prefix, sys.prefix; print(sys.prefix)'; \
	/tmp/python313-venv/bin/pip --version; \
	rm -rf /tmp/python313-venv

RUN apt-get update -y \
    && apt-get install -y git

RUN wget -O /usr/src/google-chrome-stable_current_amd64.deb "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" && \
  dpkg -i /usr/src/google-chrome-stable_current_amd64.deb ; \
  apt-get update && apt-get install -f -y && \
  rm -f /usr/src/google-chrome-stable_current_amd64.deb
RUN google-chrome --version

ENV DBUS_SESSION_BUS_ADDRESS=/dev/null

ARG HELM_VERSION=3.20.2
ARG HELM_LINUX_AMD64_SHA256=258e830a9e613c8a7a302d6059b4bb3b9758f2f3e1bb8ea0d707ce10a9a72fea
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tgz \
    && echo "${HELM_LINUX_AMD64_SHA256}  /tmp/helm.tgz" | sha256sum -c - \
    && tar -zxvf /tmp/helm.tgz -C /tmp/ \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm \
    && helm version --short \
    && rm -rf /tmp/helm.tgz /tmp/linux-amd64

ARG HELMFILE_VERSION=1.5.0
ARG HELMFILE_LINUX_AMD64_SHA256=9612fc88e626098ca8fad63aa73781850896767b3ac1be1b305c48167da062fa
RUN curl -fsSL "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz" -o /tmp/helmfile.tgz \
    && echo "${HELMFILE_LINUX_AMD64_SHA256}  /tmp/helmfile.tgz" | sha256sum -c - \
    && tar -zxvf /tmp/helmfile.tgz -C /tmp/ helmfile \
    && mv /tmp/helmfile /usr/local/bin/helmfile \
    && chmod +x /usr/local/bin/helmfile \
    && helmfile --version \
    && rm -f /tmp/helmfile.tgz

ENV HELM_PLUGINS=/usr/local/share/helm/plugins
ARG HELM_DIFF_VERSION=v3.15.6
RUN mkdir -p "${HELM_PLUGINS}" \
    && helm plugin install https://github.com/databus23/helm-diff --version "${HELM_DIFF_VERSION}" \
    && chmod -R a+rX "${HELM_PLUGINS}" \
    && helm diff version

ARG FIREFOX_VERSION=75.0
RUN wget --no-verbose -O /tmp/firefox.tar.bz2 https://download-installer.cdn.mozilla.net/pub/firefox/releases/$FIREFOX_VERSION/linux-x86_64/en-US/firefox-$FIREFOX_VERSION.tar.bz2 \
  && tar -C /opt -xjf /tmp/firefox.tar.bz2 \
  && rm /tmp/firefox.tar.bz2 \
  && ln -fs /opt/firefox/firefox /usr/bin/firefox

RUN curl -L "https://github.com/GoogleCloudPlatform/docker-credential-gcr/releases/download/v2.0.1/docker-credential-gcr_linux_amd64-2.0.1.tar.gz" \
  | tar xz --to-stdout ./docker-credential-gcr \
  > /usr/bin/docker-credential-gcr && chmod +x /usr/bin/docker-credential-gcr

COPY sudoers /etc/

# Opt-in per-process selector. It only reads; it never installs or edits.
COPY iskra-toolchain /usr/local/bin/iskra-toolchain
RUN chmod 0755 /usr/local/bin/iskra-toolchain


COPY requirements.txt /
RUN /usr/local/bin/pip3.8 install -r /requirements.txt


# `nvm use` inside a RUN does not survive the layer, so the image has no
# default Node on PATH; the nvm `default` alias stays v24.20.0 for anyone who
# sources nvm.sh. Projects pick a version with iskra-toolchain instead.
RUN apt-get update -y \
    && apt-get install -y xvfb \
    && rm -rf /var/lib/apt/lists/*

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000

RUN groupadd -g "${gid}" "${group}" \
    && useradd -l -c "Jenkins user" -d /home/"${user}" -u "${uid}" -g "${gid}" -m "${user}" \
    && groupadd -g 412 docker \
    && usermod -a -G docker "${user}" \
    && chown -R "${user}:${group}" "${NVM_DIR}"

RUN mkdir -p /etc/ssh \
    && { \
      echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"; \
      echo "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="; \
      echo "github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk="; \
    } > /etc/ssh/ssh_known_hosts

USER jenkins

ENV USE_GKE_GCLOUD_AUTH_PLUGIN=true
