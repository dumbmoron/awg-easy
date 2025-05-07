FROM alpine AS awg-build

RUN apk add git go musl-dev linux-headers gcc make

# Build amneziawg-go
ADD https://github.com/amnezia-vpn/amneziawg-go.git#2e3f7d122ca8ef61e403fddc48a9db8fccd95dbf /awg-go
ARG CGO_ENABLED=1

# taken from amneziawg-go/Dockerfile
RUN cd /awg-go && \
    go build -ldflags '-linkmode external -extldflags "-fno-PIC -static"' -v -o /awg-go/awg-go.bin

# Build amneziawg-tools
ADD https://github.com/amnezia-vpn/amneziawg-tools.git#c0b400c6dfc046f5cae8f3051b14cb61686fcf55 /awg-tools
RUN cd /awg-tools/src && \
    make -j$(nproc)

FROM docker.io/library/node:lts-alpine AS build
WORKDIR /app

# update corepack
RUN npm install --global corepack@latest
# Install pnpm
RUN corepack enable pnpm

# Copy Web UI
COPY src/package.json src/pnpm-lock.yaml ./
RUN pnpm install

# Build UI
COPY src ./
RUN pnpm build

# Copy build result to a new image.
# This saves a lot of disk space.
FROM docker.io/library/node:lts-alpine
WORKDIR /app

COPY --from=awg-build /awg-go/awg-go.bin /usr/bin/amneziawg-go
COPY --from=awg-build /awg-tools/src/wg /usr/bin/awg
COPY --from=awg-build /awg-tools/src/wg-quick/linux.bash /usr/bin/awg-quick

RUN mkdir -pm 0777 /etc/amnezia/amneziawg

RUN ln -s /usr/bin/awg /usr/bin/wg && \
    ln -s /usr/bin/awg-quick /usr/bin/wg-quick && \
    ln -s /etc/amnezia/amneziawg /etc/wireguard

HEALTHCHECK --interval=1m --timeout=5s --retries=3 CMD /usr/bin/timeout 5s /bin/sh -c "/usr/bin/wg show | /bin/grep -q interface || exit 1"

# Copy build
COPY --from=build /app/.output /app
# Copy migrations
COPY --from=build /app/server/database/migrations /app/server/database/migrations
# libsql (https://github.com/nitrojs/nitro/issues/3328)
RUN cd /app/server && \
    npm install --no-save libsql && \
    npm cache clean --force
# cli
COPY --from=build /app/cli/cli.sh /usr/local/bin/cli
RUN chmod +x /usr/local/bin/cli

# Install Linux packages
RUN apk add --no-cache \
    bash \
    dpkg \
    dumb-init \
    iptables \
    ip6tables \
    nftables \
    kmod \
    iptables-legacy \
    wireguard-tools

# Use iptables-legacy
RUN update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 10 --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-legacy-restore --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-legacy-save
RUN update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 10 --slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/ip6tables-legacy-restore --slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/ip6tables-legacy-save

# Set Environment
ENV DEBUG=Server,WireGuard,Database,CMD
ENV PORT=51821
ENV HOST=0.0.0.0
ENV INSECURE=false
ENV INIT_ENABLED=false

LABEL org.opencontainers.image.source=https://github.com/wg-easy/wg-easy

# Run Web UI
CMD ["/usr/bin/dumb-init", "node", "server/index.mjs"]
