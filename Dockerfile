# syntax=docker/dockerfile:1

# Keep these versions aligned with .ruby-version and .node-version.
ARG RUBY_VERSION=3.4.10
ARG NODE_VERSION=24.20.0
FROM --platform=linux/amd64 node:${NODE_VERSION}-bookworm-slim AS node
FROM --platform=linux/amd64 ruby:${RUBY_VERSION}-slim-bookworm AS base

WORKDIR /rails
ENV RAILS_ENV="production" \
    BUNDLE_WITHOUT="development:test:preview" \
    BUNDLE_DEPLOYMENT="1" \
    RAILS_SERVE_STATIC_FILES="true" \
    RAILS_LOG_TO_STDOUT="1" \
    GROVER_NO_SANDBOX="true" \
    PUPPETEER_CHROME_HEADLESS_SHELL_SKIP_DOWNLOAD="true" \
    PUPPETEER_CACHE_DIR="/rails/.cache/puppeteer"

# Node's official binary avoids compiling Node during every image build.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# libvips >= 8.13 is required by the Active Storage security patch.
# Chromium is downloaded by the locked Puppeteer package; only its libraries
# are installed here, so no separate Chrome repository or browser is needed.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      ca-certificates curl imagemagick libvips postgresql-client \
      fonts-liberation fonts-ipafont-gothic fonts-wqy-zenhei fonts-thai-tlwg \
      fonts-kacst fonts-freefont-ttf libasound2 libatk-bridge2.0-0 libatk1.0-0 \
      libcups2 libdbus-1-3 libdrm2 libgbm1 libgtk-3-0 libnspr4 libnss3 \
      libx11-xcb1 libxcomposite1 libxdamage1 libxfixes3 libxkbcommon0 \
      libxrandr2 libxshmfence1 libxss1 xdg-utils && \
    rm -rf /var/lib/apt/lists/*

FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libpq-dev pkg-config unzip && \
    rm -rf /var/lib/apt/lists/*

COPY --link Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf /usr/local/bundle/cache /usr/local/bundle/ruby/*/cache

COPY --link package.json package-lock.json ./
RUN npm ci --omit=dev && \
    npx puppeteer browsers install chrome && \
    npm cache clean --force

COPY --link . .
RUN SECRET_KEY_BASE=DUMMY RAILS_ENV=build ./bin/rails assets:precompile

FROM base
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

RUN useradd rails --create-home --shell /bin/bash && \
    mkdir -p /rails/tmp/pids && \
    chown -R rails:rails /rails
USER rails:rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
