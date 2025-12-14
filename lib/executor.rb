# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require_relative 'saturn_ci_worker_api/request'
require_relative 'saturn_ci_worker_api/stream'
require_relative 'saturn_ci_worker_api/docker_registry_cache'
require_relative 'buildx_output_parser'

class Executor
  LOG_PATH = '/tmp/output.log'
  PROJECT_DIR = '/repository'

  attr_reader :task_info

  def initialize
    @host = ENV.fetch('SATURNCI_API_HOST')
    @task_id = ENV.fetch('TASK_ID')
    @worker_id = ENV.fetch('WORKER_ID')
  end

  def send_worker_event(name, notes: nil)
    SaturnCIWorkerAPI::Request.new(
      host: @host,
      method: :post,
      endpoint: "workers/#{@worker_id}/worker_events",
      body: { type: name, notes: notes }.to_json
    ).execute
  rescue StandardError => e
    puts "Warning: Failed to send worker event '#{name}': #{e.message}"
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
    send_worker_event('task_fetched')

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
        send_worker_event('docker_ready')
        puts 'Docker info (registry mirrors):'
        system('docker info 2>/dev/null | grep -A5 "Registry Mirrors" || echo "No registry mirrors configured"')
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

  def authenticate_to_registry_cache
    registry_cache = SaturnCIWorkerAPI::DockerRegistryCache.new(
      username: @task_info['docker_registry_cache_username'],
      password: @task_info['docker_registry_cache_password'],
      project_name: @task_info['project_name']&.downcase,
      branch_name: @task_info['branch_name']&.downcase
    )

    puts 'Authenticating to Docker registry cache...'
    unless registry_cache.authenticate
      puts 'Warning: Docker registry cache authentication failed'
      return false
    end
    true
  end

  def build_with_cache
    registry_cache = SaturnCIWorkerAPI::DockerRegistryCache.new(
      username: @task_info['docker_registry_cache_username'],
      password: @task_info['docker_registry_cache_password'],
      project_name: @task_info['project_name']&.downcase,
      branch_name: @task_info['branch_name']&.downcase
    )

    image_url = registry_cache.image_url

    if load_cached_image(image_url)
      send_worker_event('docker_build_finished', notes: { cached_from_shared_storage: true }.to_json)
      return true
    end

    puts 'Authenticating to Docker registry cache...'
    unless registry_cache.authenticate
      puts 'Warning: Docker registry cache authentication failed, building without cache'
      return false
    end

    puts 'Creating buildx builder...'
    buildkitd_config = <<~TOML
      [registry."docker-image-registry-service:5000"]
        http = true
        insecure = true
    TOML
    File.write('/tmp/buildkitd.toml', buildkitd_config)
    system('docker buildx create --name saturnci-builder --driver docker-container --config /tmp/buildkitd.toml --use 2>/dev/null || docker buildx use saturnci-builder')

    build_command = [
      'docker buildx build',
      '--load',
      "-t #{image_url}:latest",
      "--cache-from type=registry,ref=#{image_url}:cache",
      "--cache-to type=registry,ref=#{image_url}:cache,mode=max",
      '--progress=plain',
      '-f .saturnci/Dockerfile .'
    ].join(' ')

    puts "Build command: #{build_command}"
    send_worker_event('docker_build_started')

    buildx_output, success = capture_and_stream_output("#{build_command} 2>&1")

    raise "Cache import failed: #{buildx_output[/ERROR:.*$/]}" if buildx_output.include?('failed to configure registry cache importer')

    build_metrics = BuildxOutputParser.new.parse(buildx_output)

    send_worker_event('docker_build_finished', notes: build_metrics.to_json)
    puts "Build metrics: #{build_metrics}"

    save_image_to_cache(image_url) if success

    success
  end

  def shared_cache_dir
    repository_id = ENV.fetch('REPOSITORY_ID', nil)
    commit_hash = ENV.fetch('COMMIT_HASH', nil)
    return nil unless repository_id && commit_hash

    "/shared/#{repository_id}/#{commit_hash}"
  end

  def cached_image_path
    dir = shared_cache_dir
    return nil unless dir

    "#{dir}/image.tar"
  end

  def load_cached_image(image_url)
    path = cached_image_path
    return false unless path && File.exist?(path)

    puts "Found cached image at #{path}"
    send_worker_event('docker_build_started', notes: { loading_from_cache: true }.to_json)

    puts 'Loading cached image...'
    start_time = Time.now
    success = system("docker load < #{path}")
    load_time = (Time.now - start_time).round(1)

    if success
      puts "Cached image loaded in #{load_time}s"
      system("docker tag $(docker images -q | head -1) #{image_url}:latest")
      true
    else
      puts 'Failed to load cached image, will rebuild'
      false
    end
  end

  def save_image_to_cache(image_url)
    dir = shared_cache_dir
    return unless dir

    puts "Saving image to cache at #{dir}..."
    FileUtils.mkdir_p(dir)

    start_time = Time.now
    success = system("docker save #{image_url}:latest > #{cached_image_path}")
    save_time = (Time.now - start_time).round(1)

    if success
      puts "Image saved to cache in #{save_time}s"
    else
      puts 'Warning: Failed to save image to cache'
    end
  end

  private

  def capture_and_stream_output(command)
    output = ''
    status = nil
    Open3.popen2e(command) do |_stdin, stdout_and_stderr, wait_thr|
      stdout_and_stderr.each_line do |line|
        puts line
        output += line
      end
      status = wait_thr.value
    end
    [output, status.success?]
  end
end
