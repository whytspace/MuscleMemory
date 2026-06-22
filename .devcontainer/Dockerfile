FROM mcr.microsoft.com/devcontainers/base:bookworm

ARG STYLUA_VERSION=2.5.2
ARG LUA_LANGUAGE_SERVER_VERSION=3.18.2

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    liblua5.1-0-dev \
    lua5.1 \
    luarocks \
    tar \
    unzip \
  && luarocks --lua-version=5.1 install luacheck \
  && luarocks --lua-version=5.1 install busted \
  && luarocks --lua-version=5.1 install luacov \
  && arch="$(dpkg --print-architecture)" \
  && case "$arch" in \
    amd64) stylua_arch="linux-x86_64"; lls_arch="linux-x64" ;; \
    arm64) stylua_arch="linux-aarch64"; lls_arch="linux-arm64" ;; \
    *) echo "Unsupported architecture for StyLua: $arch" >&2; exit 1 ;; \
  esac \
  && curl -fsSL \
    "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-${stylua_arch}.zip" \
    -o /tmp/stylua.zip \
  && unzip -q /tmp/stylua.zip -d /usr/local/bin \
  && chmod +x /usr/local/bin/stylua \
  && mkdir -p /opt/lua-language-server \
  && curl -fsSL \
    "https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LANGUAGE_SERVER_VERSION}/lua-language-server-${LUA_LANGUAGE_SERVER_VERSION}-${lls_arch}.tar.gz" \
    -o /tmp/lua-language-server.tar.gz \
  && tar -xzf /tmp/lua-language-server.tar.gz -C /opt/lua-language-server \
  && ln -s /opt/lua-language-server/bin/lua-language-server /usr/local/bin/lua-language-server \
  && rm -rf /tmp/stylua.zip /tmp/lua-language-server.tar.gz /var/lib/apt/lists/*
