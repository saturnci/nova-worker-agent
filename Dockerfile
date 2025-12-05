FROM ruby:3.3.5

# Install Docker CLI (for talking to DinD sidecar)
RUN apt-get update && apt-get install -y \
    docker.io \
    docker-compose \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /nova_worker_agent

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' && bundle install

COPY . .

# Entry point - Rails/RSpec adapter is the default
CMD ["ruby", "bin/adapters/rails_rspec"]
