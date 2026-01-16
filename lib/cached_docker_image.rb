# frozen_string_literal: true

require 'English'
require 'fileutils'
require_relative 'benchmarking'

class Executor
  class CachedDockerImage
    def initialize(image_name:, cache_path:, cache_key:)
      @image_name = image_name
      @cache_path = cache_path
      @cache_key = cache_key
      @cache_key_path = "#{File.dirname(cache_path)}/cache_key.txt"
    end

    def load
      unless cache_key_matches?
        puts 'CACHE MISS: cache key mismatch (Gemfile.lock or Dockerfile changed)'
        return false
      end

      if image_exists_in_docker?
        puts "CACHE HIT: #{@image_name} (already in Docker)"
        return true
      end

      unless File.exist?(@cache_path)
        puts "CACHE MISS: #{@image_name} (no cached tar at #{@cache_path})"
        return false
      end

      puts "CACHE HIT: #{@image_name} (loading from #{@cache_path}, #{file_size_mb} MB)"

      output, success, duration = run_docker_load

      if success
        puts output
        puts "  Loaded in #{duration}s"
        true
      else
        puts "  Failed to load from cache: #{output}"
        false
      end
    end

    def image_exists_in_docker?
      system("docker image inspect #{@image_name} > /dev/null 2>&1")
    end

    def save
      puts "Saving #{@image_name} to #{@cache_path}..."
      FileUtils.mkdir_p(File.dirname(@cache_path))

      _, duration = Benchmarking.duration { system("docker save #{@image_name} > #{@cache_path}") }

      File.write(@cache_key_path, @cache_key)
      puts "Saved #{@image_name} in #{duration}s (#{file_size_mb} MB)"
    end

    def run_docker_load
      output = nil
      success, duration = Benchmarking.duration do
        output = `docker load < #{@cache_path} 2>&1`
        $CHILD_STATUS.success?
      end
      [output, success, duration]
    end

    private

    def cache_key_matches?
      return false unless File.exist?(@cache_key_path)

      File.read(@cache_key_path).strip == @cache_key
    end

    def file_size_mb
      return 0 unless File.exist?(@cache_path)

      (File.size(@cache_path) / 1024.0 / 1024.0).round(1)
    end
  end
end
