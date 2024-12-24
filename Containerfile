ARG RUBY_VERSION=3.3.6

FROM ghcr.io/scriptonbasestar/forem-ruby:${RUBY_VERSION} AS base

## ==================================================================================================
## ==================================================================================================
## ==================================================================================================
FROM base AS builder

# This is provided by BuildKit
ARG TARGETARCH

USER root

ENV BUNDLER_VERSION=2.6.1 \
    BUNDLE_SILENCE_ROOT_WARNING=true \
    BUNDLE_SILENCE_DEPRECATIONS=true

RUN gem install -N bundler:"${BUNDLER_VERSION}"

ENV APP_USER=forem APP_UID=1000 APP_GID=1000 APP_HOME=/opt/apps/forem \
    LD_PRELOAD=libjemalloc.so.2
RUN mkdir -p ${APP_HOME} && chown "${APP_UID}":"${APP_GID}" "${APP_HOME}" && \
    groupadd -g "${APP_GID}" "${APP_USER}" && \
    adduser --uid "${APP_UID}" --gid "${APP_GID}" --home "${APP_HOME}" "${APP_USER}"

ENV DOCKERIZE_VERSION=v0.9.1
RUN curl -fsSLO https://github.com/jwilder/dockerize/releases/download/"${DOCKERIZE_VERSION}"/dockerize-linux-${TARGETARCH}-"${DOCKERIZE_VERSION}".tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-${TARGETARCH}-"${DOCKERIZE_VERSION}".tar.gz \
    && rm dockerize-linux-${TARGETARCH}-"${DOCKERIZE_VERSION}".tar.gz \
    && chown root:root /usr/local/bin/dockerize

USER "${APP_USER}"
WORKDIR "${APP_HOME}"

COPY --chown=${APP_UID}:${APP_GID} ./.ruby-version "${APP_HOME}"/
COPY --chown=${APP_UID}:${APP_GID} ./Gemfile ./Gemfile.lock "${APP_HOME}"/
# COPY --chown=${APP_UID}:${APP_GID} ./vendor/cache "${APP_HOME}"/vendor/cache

# Bundler 설정: GEM_HOME과 BUNDLE_PATH을 사용자 소유 디렉토리로 설정
ENV GEM_HOME="${APP_HOME}/.gem" \
    BUNDLE_PATH="${APP_HOME}/vendor/bundle" \
    BUNDLE_APP_CONFIG="${APP_HOME}/.bundle"

# Have to reset APP_CONFIG, which appears to be set by upstream images, to
# avoid permission errors in the development/test images (which run bundle
# as a user and require write access to the config file for setting things
# like BUNDLE_WITHOUT (a value that is cached by root here in this builder
# layer, see https://michaelheap.com/bundler-ignoring-bundle-without/))
RUN mkdir -p "${BUNDLE_APP_CONFIG}" && \
    touch "${BUNDLE_APP_CONFIG}/config" && \
    chown -R "${APP_UID}:${APP_GID}" "${BUNDLE_APP_CONFIG}"

# Bundler 설정 업데이트
RUN bundle config --local build.sassc --disable-march-tune-native && \
    bundle config --local without development:test
# RUN bundle config set --local path "${BUNDLE_PATH}" && \
#     bundle config set --local without 'development test' && \
#     bundle config set --local build.sassc --disable-march-tune-native

RUN bundle config set deployment true && \
    BUNDLE_FROZEN=true bundle install --jobs 4 --retry 5 && \
    find "${APP_HOME}"/vendor/bundle -name "*.c" -delete && \
    find "${APP_HOME}"/vendor/bundle -name "*.o" -delete

COPY --chown=${APP_UID}:${APP_GID} . "${APP_HOME}"

RUN mkdir -p "${APP_HOME}"/public/{assets,images,packs,podcasts,uploads}

# While it's relatively rare for bare metal builds to hit the default
# timeout, QEMU-based ones (as is the case with Docker BuildX for
# cross-compiling) quite often can. This increased timeout should help
# reduce false-negatives when building multiarch images.
RUN echo 'httpTimeout: 300000' >> ~/.yarnrc.yml

# This is one giant step now because previously, removing node_modules to save
# layer space was done in a later step, which is invalid in at least some
# Docker storage drivers (resulting in Directory Not Empty errors).
RUN NODE_ENV=production yarn install && \
    RAILS_ENV=production NODE_ENV=production bundle exec rake assets:precompile && \
    rm -rf node_modules

# This used to be calculated within the container build, but we then tried
# to rm -rf the .git that was copied in, which isn't valid (removing
# directories created in lower layers of an image isn't a thing (at least
# with the overlayfs drivers). Instead, we'll pass this in over CLI when
# building images (eg. in CI), but leave a default value for callers who don't
# override (perhaps docker-compose). This isn't perfect, but it'll do for now.
ARG VCS_REF=unspecified

RUN echo $(date -u +'%Y-%m-%dT%H:%M:%SZ') >> "${APP_HOME}"/FOREM_BUILD_DATE && \
    echo "${VCS_REF}" >> "${APP_HOME}"/FOREM_BUILD_SHA

## ==================================================================================================
## ==================================================================================================
## ==================================================================================================
## Production
FROM base AS production

USER root

ENV APP_USER=forem APP_UID=1000 APP_GID=1000 APP_HOME=/opt/apps/forem \
    LD_PRELOAD=libjemalloc.so.2
RUN mkdir -p ${APP_HOME} && chown "${APP_UID}":"${APP_GID}" "${APP_HOME}" && \
    groupadd -g "${APP_GID}" "${APP_USER}" && \
    adduser --uid "${APP_UID}" --gid "${APP_GID}" --home "${APP_HOME}" "${APP_USER}"

COPY --from=builder --chown="${APP_USER}":"${APP_USER}" ${APP_HOME} ${APP_HOME}

USER "${APP_USER}"
WORKDIR "${APP_HOME}"

VOLUME "${APP_HOME}"/public/

ENTRYPOINT ["./scripts/entrypoint.sh"]

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]


## ==================================================================================================
## ==================================================================================================
## ==================================================================================================
## Testing
FROM builder AS testing

USER "${APP_USER}"

COPY --chown="${APP_USER}":"${APP_USER}" ./spec "${APP_HOME}"/spec
COPY --from=builder /usr/local/bin/dockerize /usr/local/bin/dockerize

RUN bundle config --local build.sassc --disable-march-tune-native && \
    bundle config --delete without && \
    bundle config set deployment true && \
    BUNDLE_FROZEN=true bundle install --jobs 4 --retry 5 && \
    find "${APP_HOME}"/vendor/bundle -name "*.c" -delete && \
    find "${APP_HOME}"/vendor/bundle -name "*.o" -delete

ENTRYPOINT ["./scripts/entrypoint.sh"]

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]


## ==================================================================================================
## ==================================================================================================
## ==================================================================================================
FROM builder AS uffizzi

USER "${APP_USER}"

COPY --chown="${APP_USER}":"${APP_USER}" ./spec "${APP_HOME}"/spec
COPY --from=builder /usr/local/bin/dockerize /usr/local/bin/dockerize

RUN bundle config --local build.sassc --disable-march-tune-native && \
    bundle config --delete without && \
    bundle config set deployment true && \
    BUNDLE_FROZEN=true bundle install --jobs 4 --retry 5 && \
    find "${APP_HOME}"/vendor/bundle -name "*.c" -delete && \
    find "${APP_HOME}"/vendor/bundle -name "*.o" -delete

# Replacement for volume
COPY --from=builder --chown="${APP_USER}":"${APP_USER}" ${APP_HOME} ${APP_HOME}
## Bund install
RUN ./scripts/bundle.sh
## Yarn install
RUN bash -c yarn install --dev

# Document that we're going to expose port 3000
EXPOSE 3000
# Use Bash as the default command
CMD ["/bin/bash"]

## ==================================================================================================
## ==================================================================================================
## ==================================================================================================
## Development
FROM base AS development

ENV TMPDIR=/var/tmp

# Application dependencies, for Cypress, node-canvas
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=tmpfs,target=/var/log \
    apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
      libgtk2.0-0 libgtk-3-0 libgbm-dev libnotify-dev libgconf-2-4 libnss3 libxss1 libasound2 libxtst6 xauth xvfb \
      libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev

# Installing hivemind
ARG TARGETARCH
ENV HIVEMIND_VERSION=v1.1.0
ADD https://github.com/DarthSim/hivemind/releases/download/${HIVEMIND_VERSION}/hivemind-${HIVEMIND_VERSION}-linux-${TARGETARCH}.gz /tmp/hivemind.gz
RUN gunzip /tmp/hivemind.gz && \
    chmod +x /tmp/hivemind && \
    mv /tmp/hivemind /usr/local/bin/hivemind && \
    rm -rf /tmp/*

# Configure bundler
ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3

# Store Bundler settings in the project's root
ENV BUNDLE_APP_CONFIG=.bundle

# Uncomment this line if you want to run binstubs without prefixing with `bin/` or `bundle exec`
# ENV PATH /app/bin:$PATH

# Upgrade RubyGems and install the latest Bundler version
RUN gem update --system && \
    gem install bundler

# RUN bundle config --local build.sassc --disable-march-tune-native && \
#     bundle config --delete without && \
#     bundle config set deployment true && \
#     BUNDLE_FROZEN=true bundle install --jobs 4 --retry 5 && \
#     find "${APP_HOME}"/vendor/bundle -name "*.c" -delete && \
#     find "${APP_HOME}"/vendor/bundle -name "*.o" -delete

# Create a directory for the app code
RUN mkdir -p /workspaces
WORKDIR /workspaces

# Document that we're going to expose port 3000
EXPOSE 3000
# Use Bash as the default command
CMD ["/bin/bash"]
