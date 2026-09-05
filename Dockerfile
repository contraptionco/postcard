# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.2.2

FROM --platform=linux/amd64 ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
  BUNDLE_WITHOUT="development:test" \
  BUNDLE_DEPLOYMENT="1" \
  RAILS_SERVE_STATIC_FILES="true" \
  DEBIAN_FRONTEND="noninteractive" \
  GROVER_NO_SANDBOX="true"


# Update gems and bundler
# Pin RubyGems to 3.5.x because tailwindcss-rails 2.0.25 uses Gem::Platform.match,
# which was removed in RubyGems 3.6+
RUN gem update --system 3.5.22 --no-document && \
  gem install -N bundler


# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems and node modules
RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y build-essential curl libpq-dev libvips node-gyp pkg-config python-is-python3 dbus dbus-x11 && \
  service dbus start

# Install JavaScript dependencies
ARG NODE_VERSION=18.12.1
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
  /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
  rm -rf /tmp/node-build-master

# Install application gems
COPY --link Gemfile Gemfile.lock ./
RUN bundle install && \
  rm -rf ~/.bundle/ $BUNDLE_PATH/ruby/*/cache $BUNDLE_PATH/ruby/*/bundler/gems/*/.git

# Install node modules
COPY --link package.json ./
RUN npm install

# Copy application code
COPY --link . .

# Precompiling assets using build environment (production-like but without AWS dependencies)
RUN SECRET_KEY_BASE=DUMMY RAILS_ENV=build ./bin/rails assets:clobber
RUN SECRET_KEY_BASE=DUMMY RAILS_ENV=build ./bin/rails assets:precompile

# Final stage for app image
FROM base

# Install packages needed for deployment
RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y curl imagemagick libvips postgresql-client && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Puppeteer deps
RUN apt-get update \
  && apt-get install -y wget gnupg \
  && wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
  && sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' \
  && apt-get update \
  && apt-get install -y fonts-ipafont-gothic fonts-wqy-zenhei fonts-thai-tlwg fonts-kacst fonts-freefont-ttf libxss1 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon-x11-0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2 libnss3 libgtk-3-0 xvfb x11-apps x11-xkb-utils libx11-6 libx11-xcb1 \
  libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libatk1.0-0 libc6 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 libnspr4 libpangocairo-1.0-0 libstdc++6 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget \
  --no-install-recommends

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Copy Node.js and node_modules from build stage
COPY --from=build /usr/local/node /usr/local/node
COPY --from=build /rails/node_modules /rails/node_modules
ENV PATH=/usr/local/node/bin:$PATH


# Run and own only the runtime files as a non-root user for security
RUN useradd rails --create-home --shell /bin/bash && \
  chown -R rails:rails /rails && \
  chown -R rails:rails db log storage tmp /rails/node_modules
USER rails:rails

# Deployment options
ENV RAILS_LOG_TO_STDOUT="1" \
  RAILS_SERVE_STATIC_FILES="true"

# Set up dbus
RUN mkdir -p /home/rails/.dbus && chown -R rails:rails /home/rails/.dbus
ENV DBUS_SESSION_BUS_ADDRESS=/home/rails/.dbus/system_bus_socket

# Set up Puppeteer environment
ENV PUPPETEER_CACHE_DIR=/home/rails/.cache/puppeteer \
  PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=false

# Create Puppeteer cache directory with correct permissions
RUN mkdir -p $PUPPETEER_CACHE_DIR && \
  chown -R rails:rails $PUPPETEER_CACHE_DIR

# Install Puppeteer and Chrome
RUN cd /rails && \
  npm install puppeteer && \
  npx puppeteer browsers install chrome

# Entrypoint sets up the container.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
