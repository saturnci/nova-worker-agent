# frozen_string_literal: true

require 'fileutils'
require 'json'
require_relative 'saturn_ci_worker_api/request'
require_relative 'saturn_ci_worker_api/stream'

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

  def kill_stream
    sleep 2
    @stream.kill
  end
end
