# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require_relative 'saturn_ci_worker_api/request'
require_relative 'saturn_ci_worker_api/stream'
require_relative 'buildx_output_parser'
require_relative 'executor/docker_compose_configuration'
require_relative 'saturn_ci_worker_api_client'
require_relative 'cached_docker_image'
require_relative 'benchmarking'

class Executor
  LOG_PATH = '/tmp/output.log'

  def self.project_dir
    ENV.fetch('PROJECT_DIR', '/repository')
  end

  attr_reader :task_info

  def initialize
    @host = ENV.fetch('SATURNCI_API_HOST')
    @task_id = ENV.fetch('TASK_ID')
    @worker_id = ENV.fetch('WORKER_ID')
    @client = SaturnCIWorkerAPIClient.new(host: @host)
  end

  def send_worker_event(name, notes: nil)
    @client.post("workers/#{@worker_id}/worker_events", { type: name, notes: notes })
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

    response = @client.get("tasks/#{@task_id}")
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
    token_response = @client.post('github_tokens', { github_installation_id: @task_info['github_installation_id'] })
    github_token = token_response.body

    puts "Cloning #{@task_info['github_repo_full_name']}..."
    FileUtils.rm_rf(self.class.project_dir)
    clone_command = "git clone --recurse-submodules https://x-access-token:#{github_token}@github.com/#{@task_info['github_repo_full_name']} #{self.class.project_dir}"
    system(clone_command)

    Dir.chdir(self.class.project_dir)
    puts "Checking out commit #{@task_info['commit_hash']}..."
    system("git checkout #{@task_info['commit_hash']}")

    puts 'Repo cloned and checked out successfully.'
    system('ls -la 2>&1')
  end

  def write_env_file
    env_file_path = File.join(self.class.project_dir, '.saturnci/.env')
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
      response = @client.get("tasks/#{@task_id}")
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
    response = @client.post("tasks/#{@task_id}/task_finished_events")
    puts "Task finished response code: #{response.code}"
    puts "Task finished response body: #{response.body}" unless response.body.to_s.empty?
  end

  def clean_up_docker
    project = "task-#{@task_id}"
    puts "Cleaning up Docker resources for project #{project}..."
    system("docker-compose -p #{project} -f .saturnci/docker-compose.yml down --volumes --remove-orphans 2>&1")
  end

  def wait_for_docker_daemon(timeout: 120)
    print 'Waiting for Docker daemon'
    start_time = Time.now

    loop do
      if system('docker info > /dev/null 2>&1')
        puts
        puts 'Docker daemon is ready.'
        send_worker_event('docker_ready')
        puts 'Docker info (registry mirrors):'
        system('docker info 2>/dev/null | grep -A5 "Registry Mirrors" || echo "No registry mirrors configured"')
        output_cache_status
        return true
      end

      if Time.now - start_time > timeout
        puts
        raise "Timed out waiting for Docker daemon after #{timeout} seconds."
      end

      print '.'
      sleep 1
    end
  end

  def output_cache_status
    repo_id = ENV.fetch('REPOSITORY_ID')
    tsr_id = @task_info['test_suite_run_id']
    status_file = "/dind-cache-base/#{repo_id}/cache_status_#{tsr_id}.txt"

    if File.exist?(status_file)
      puts File.read(status_file)
    else
      puts "Cache status file not found: #{status_file}"
    end
  end

  def preload_app_image
    cache_key = compute_cache_key
    tagged_image_name = "saturnci-local:#{cache_key}"

    if load_cached_image(tagged_image_name)
      system("docker tag #{tagged_image_name} saturnci-local")
      return true
    end

    build_command = [
      'docker build',
      "-t #{tagged_image_name}",
      '--progress=plain',
      '-f .saturnci/Dockerfile .'
    ].join(' ')

    puts "Build command: #{build_command}"
    send_worker_event('docker_build_started')

    buildx_output, success = capture_and_stream_output("#{build_command} 2>&1")

    build_metrics = BuildxOutputParser.new.parse(buildx_output)

    send_worker_event('docker_build_finished', notes: build_metrics.to_json)
    puts "Build metrics: #{build_metrics}"

    if success
      save_image_to_cache(tagged_image_name)
      system("docker tag #{tagged_image_name} saturnci-local")
    end

    success
  end

  def shared_cache_dir
    "/shared/#{ENV.fetch('REPOSITORY_ID')}"
  end

  def cached_image_path
    "#{shared_cache_dir}/image.tar"
  end

  def compute_cache_key
    gemfile_lock = begin
      File.read("#{self.class.project_dir}/Gemfile.lock")
    rescue StandardError
      ''
    end
    dockerfile = begin
      File.read("#{self.class.project_dir}/.saturnci/Dockerfile")
    rescue StandardError
      ''
    end
    Digest::SHA256.hexdigest(gemfile_lock + dockerfile)[0..15]
  end

  def load_cached_image(image_url)
    cache_key = compute_cache_key
    cached_image = CachedDockerImage.new(image_name: image_url, cache_path: cached_image_path, cache_key: cache_key)

    puts 'Checking app image cache...'
    send_worker_event('docker_build_started', notes: { loading_from_cache: true }.to_json)
    send_worker_event('app_image_load_started')
    success, duration = Benchmarking.duration { cached_image.load }
    send_worker_event('app_image_load_finished', notes: { load_time_seconds: duration }.to_json)

    if success
      system("docker tag #{image_url} saturnci-local")
      true
    else
      false
    end
  end

  def save_image_to_cache(image_url)
    cache_key = compute_cache_key
    CachedDockerImage.new(image_name: image_url, cache_path: cached_image_path, cache_key: cache_key).save
  end

  def preload_vendor_images
    puts 'Preloading vendor images...'
    docker_compose_content = File.read('.saturnci/docker-compose.yml')
    config = DockerComposeConfiguration.new(docker_compose_content)
    config.vendor_images.each do |image_name|
      pull_vendor_image(image_name)
    end
  end

  def pull_vendor_image(image_name)
    if system("docker image inspect #{image_name} > /dev/null 2>&1")
      puts "Image #{image_name} already cached"
      return true
    end

    puts "Pulling #{image_name}..."
    system("docker pull #{image_name}")
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
