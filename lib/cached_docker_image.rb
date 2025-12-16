# frozen_string_literal: true

require 'fileutils'
require_relative 'benchmarking'

class Executor
  class CachedDockerImage
    def initialize(image_name:, cache_path:)
      @image_name = image_name
      @cache_path = cache_path
    end

    def load
      if image_exists_in_docker?
        puts "NODE CACHE HIT: #{@image_name} (already in Docker)"
        return true
      end

      unless File.exist?(@cache_path)
        puts "NODE CACHE MISS: #{@image_name} (no cached tar)"
        return false
      end

      puts "NODE CACHE HIT: #{@image_name} (#{file_size_mb} MB)"

      success, duration = Benchmarking.duration { system("docker load < #{@cache_path}") }

      if success
        puts "  Loaded in #{duration}s"
        true
      else
        puts '  Failed to load from cache'
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

      puts "Saved #{@image_name} in #{duration}s (#{file_size_mb} MB)"
    end

    private

    def file_size_mb
      return 0 unless File.exist?(@cache_path)

      (File.size(@cache_path) / 1024.0 / 1024.0).round(1)
    end
  end
end
