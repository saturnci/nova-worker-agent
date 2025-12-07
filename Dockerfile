FROM ruby:3.3.5

# Install Docker CLI (for talking to DinD sidecar)
RUN apt-get update && apt-get install -y \
    docker.io \
    docker-compose \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Docker Buildx plugin (to /usr/local so it's not hidden by volume mounts)
RUN mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -SL https://github.com/docker/buildx/releases/download/v0.12.1/buildx-v0.12.1.linux-amd64 \
    -o /usr/local/lib/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

WORKDIR /nova_worker_agent

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' && bundle install

COPY . .

# Entry point - Rails/RSpec adapter is the default
CMD ["ruby", "bin/adapters/rails_rspec"]
