# Debian avoids the DNS resolution issues encountered with Alpine in production.
ARG ELIXIR_VERSION=1.19.4
ARG OTP_VERSION=28.3
ARG DEBIAN_VERSION=trixie-20260406-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git brotli \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config before compiling dependencies so config changes invalidate that layer.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Localize ships only en/und CLDR data; fetch fi.etf, sv-FI.etf, etc. at
# build time so display_name lookups don't crash when the customer switches.
RUN mix localize.download_locales

RUN mix assets.setup

COPY priv priv

COPY lib lib

RUN mix compile

COPY assets assets

RUN mix assets.deploy

# Brotli copies beside the digester's .gz ones; the render-blocking CSS is about a
# fifth smaller than gzip. Plug.Static serves them (endpoint.ex).
RUN find priv/static -name '*.gz' -exec sh -c 'brotli --best --keep "${1%.gz}"' _ {} \;

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# Keep build tools and source files out of the runtime image.
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Pinned for deterministic layout/fonts vs local dev (scripts/install-typst.sh,
# ci.yml; bump all three together). `typst --version`
# smoke-tests install: `tar` can exit 0 with nothing extracted if the
# filter arg drifts past a release rename. curl/xz purged same layer.
ARG TYPST_VERSION=0.14.2
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl xz-utils \
  && curl --fail-with-body -sSL "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-x86_64-unknown-linux-musl.tar.xz" \
     | tar -xJ --strip-components=1 -C /usr/local/bin "typst-x86_64-unknown-linux-musl/typst" \
  && typst --version \
  && apt-get purge -y curl xz-utils \
  && apt-get autoremove -y \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/edenflowers ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
