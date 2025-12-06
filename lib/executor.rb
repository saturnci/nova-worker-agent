# frozen_string_literal: true

require 'fileutils'
require 'json'
require_relative 'saturn_ci_worker_api/request'
require_relative 'saturn_ci_worker_api/stream'
require_relative 'saturn_ci_worker_api/docker_registry_cache'

class Executor
  LOG_PATH = '/tmp/output.log'
  PROJECT_DIR = '/app'

  attr_reader :task_info

  def initialize
    @host = ENV.fetch('SATURNCI_API_HOST')
    @task_id = ENV.fetch('TASK_ID')
  end

  def start_stream
    File.write(LOG_PATH, '')
    $stdout.reopen(LOG_PATH, 'a')
    $stdout.sync = true

    @stream = SaturnCIWorkerAPI::Stream.new(
      LOG_PATH,
      "tasks/#{@task_id}/system_logs",
      wait_interval: 1
    )
    @stream.start
    sleep 1

    puts "Task ID: \"#{@task_id}\""

    response = SaturnCIWorkerAPI::Request.new(
      host: @host,
      method: :get,
      endpoint: "tasks/#{@task_id}"
    ).execute
    @task_info = JSON.parse(response.body)

    puts <<~OUTPUT
      Task info received:
        github_repo_full_name: #{@task_info['github_repo_full_name']}
        branch_name: #{@task_info['branch_name']}
        commit_hash: #{@task_info['commit_hash']}
        github_installation_id: #{@task_info['github_installation_id']}
        rspec_seed: #{@task_info['rspec_seed']}
        run_order_index: #{@task_info['run_order_index']}
        number_of_concurrent_runs: #{@task_info['number_of_concurrent_runs']}
        env_vars: [#{@task_info['env_vars'].keys.join(', ')}]
    OUTPUT
  end

  def clone_repo
    puts 'Getting GitHub token...'
    token_response = SaturnCIWorkerAPI::Request.new(
      host: @host,
      method: :post,
      endpoint: 'github_tokens',
      body: { github_installation_id: @task_info['github_installation_id'] }.to_json
    ).execute
    github_token = token_response.body

    puts "Cloning #{@task_info['github_repo_full_name']}..."
    FileUtils.rm_rf(PROJECT_DIR)
    clone_command = "git clone --recurse-submodules https://x-access-token:#{github_token}@github.com/#{@task_info['github_repo_full_name']} #{PROJECT_DIR}"
    system(clone_command)

    Dir.chdir(PROJECT_DIR)
    puts "Checking out commit #{@task_info['commit_hash']}..."
    system("git checkout #{@task_info['commit_hash']}")

    puts 'Repo cloned and checked out successfully.'
    system('ls -la 2>&1')
  end

  def write_env_file
    env_file_path = File.join(PROJECT_DIR, '.saturnci/.env')
    puts "Writing env vars to #{env_file_path}..."

    File.open(env_file_path, 'w') do |file|
      @task_info['env_vars'].each do |key, value|
        file.puts "#{key}=#{value}"
      end
    end

    puts 'Env file written successfully.'
  end

  def kill_stream
    sleep 2
    @stream.kill
  end

  def finish
    puts 'Sending task finished event...'
    response = SaturnCIWorkerAPI::Request.new(
      host: @host,
      method: :post,
      endpoint: "tasks/#{@task_id}/task_finished_events"
    ).execute
    puts "Task finished response code: #{response.code}"
    puts "Task finished response body: #{response.body}" unless response.body.to_s.empty?
  end

  def wait_for_docker(timeout: 60)
    print 'Waiting for Docker daemon'
    start_time = Time.now

    loop do
      if system('docker info > /dev/null 2>&1')
        puts
        puts 'Docker daemon is ready.'
        return true
      end

      if Time.now - start_time > timeout
        puts
        puts "Timed out waiting for Docker daemon after #{timeout} seconds."
        return false
      end

      print '.'
      sleep 1
    end
  end

  def build_with_cache
    registry_cache = SaturnCIWorkerAPI::DockerRegistryCache.new(
      username: @task_info['docker_registry_cache_username'],
      password: @task_info['docker_registry_cache_password'],
      project_name: @task_info['project_name']&.downcase,
      branch_name: @task_info['branch_name']&.downcase
    )

    puts 'Authenticating to Docker registry cache...'
    unless registry_cache.authenticate
      puts 'Warning: Docker registry cache authentication failed, building without cache'
      return false
    end

    puts 'Creating buildx builder...'
    system('docker buildx create --name saturnci-builder --driver docker-container --use 2>/dev/null || docker buildx use saturnci-builder')

    image_url = registry_cache.image_url
    build_command = [
      'docker buildx build',
      '--push',
      "-t #{image_url}:latest",
      "--cache-from type=registry,ref=#{image_url}:cache",
      "--cache-to type=registry,ref=#{image_url}:cache,mode=max",
      '--progress=plain',
      '-f .saturnci/Dockerfile .'
    ].join(' ')

    puts "Build command: #{build_command}"
    result = system("#{build_command} 2>&1")
    puts "Build result: #{result ? 'success' : 'failed'}"
    result
  end
end
