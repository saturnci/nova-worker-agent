# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require_relative 'saturn_ci_worker_api/request'
require_relative 'saturn_ci_worker_api/stream'
require_relative 'saturn_ci_worker_api/docker_registry_cache'
require_relative 'buildx_output_parser'
require_relative 'executor/docker_compose_configuration'
require_relative 'cached_docker_image'
require_relative 'benchmarking'

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

  def wait_for_setup_complete
    puts 'Waiting for setup to complete...'
    loop do
      response = SaturnCIWorkerAPI::Request.new(
        host: @host,
        method: :get,
        endpoint: "tasks/#{@task_id}"
      ).execute
      task_data = JSON.parse(response.body)

      if task_data['setup_completed']
        puts 'Setup complete, proceeding...'
        return
      end

      puts 'Setup not complete yet, polling...'
      sleep 2
    end
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

  def preload_app_image
    registry_cache = SaturnCIWorkerAPI::DockerRegistryCache.new(
      username: @task_info['docker_registry_cache_username'],
      password: @task_info['docker_registry_cache_password'],
      project_name: @task_info['project_name']&.downcase,
      branch_name: @task_info['branch_name']&.downcase
    )

    image_url = registry_cache.image_url

    return true if load_cached_image("#{image_url}:latest")

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

    if success
      save_image_to_cache("#{image_url}:latest")
      puts 'Tagging as saturnci-local...'
      system("docker tag #{image_url}:latest saturnci-local")
    end

    success
  end

  def shared_cache_dir
    "/shared/#{ENV.fetch('REPOSITORY_ID')}"
  end

  def cached_image_path
    "#{shared_cache_dir}/image.tar"
  end

  def load_cached_image(image_url)
    cached_image = CachedDockerImage.new(image_name: image_url, cache_path: cached_image_path)
    return false unless File.exist?(cached_image_path)

    send_worker_event('docker_build_started', notes: { loading_from_cache: true }.to_json)
    send_worker_event('app_image_load_started')
    success, duration = Benchmarking.duration { cached_image.load }
    send_worker_event('app_image_load_finished', notes: { load_time_seconds: duration }.to_json)

    if success
      puts 'Tagging as saturnci-local...'
      system("docker tag #{image_url} saturnci-local")
      true
    else
      puts 'Will rebuild'
      false
    end
  end

  def save_image_to_cache(image_url)
    CachedDockerImage.new(image_name: image_url, cache_path: cached_image_path).save
  end

  def preload_vendor_images
    puts 'Preloading vendor images...'
    docker_compose_content = File.read('.saturnci/docker-compose.yml')
    config = DockerComposeConfiguration.new(docker_compose_content)
    config.vendor_images.each do |image_name|
      ensure_vendor_image(image_name)
    end
  end

  def ensure_vendor_image(image_name)
    return true if load_vendor_image(image_name)

    puts "Pulling #{image_name}..."
    system("docker pull #{image_name}")
    save_vendor_image(image_name)
    true
  end

  def vendor_image_cache_path(image_name)
    safe_name = image_name.tr('/', '_').tr(':', '_')
    "/shared/images/#{safe_name}/image.tar"
  end

  def load_vendor_image(image_name)
    CachedDockerImage.new(image_name: image_name, cache_path: vendor_image_cache_path(image_name)).load
  end

  def save_vendor_image(image_name)
    CachedDockerImage.new(image_name: image_name, cache_path: vendor_image_cache_path(image_name)).save
  end

  def show_cache_status
    cache_base_path = ENV.fetch('CACHE_BASE_PATH', '/var/lib/saturnci-docker')
    repository_id = ENV.fetch('REPOSITORY_ID')
    cache_path = "#{cache_base_path}/#{repository_id}"

    puts "Docker cache status for repository #{repository_id}:"
    puts 'Unclaimed caches:'
    system("ls -la #{cache_path}/unclaimed/ 2>/dev/null || echo '  (none)'")
    puts 'Claimed caches:'
    system("ls -la #{cache_path}/ 2>/dev/null | grep -v unclaimed || echo '  (none)'")
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
