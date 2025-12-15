# frozen_string_literal: true

require 'fileutils'

class Executor
  class CachedDockerImage
    def initialize(image_name:, cache_path:)
      @image_name = image_name
      @cache_path = cache_path
    end

    def load
      return false unless File.exist?(@cache_path)

      puts "Found cached image at #{@cache_path} (#{file_size_mb} MB)"

      start_time = Time.now
      success = system("docker load < #{@cache_path}")
      load_time = (Time.now - start_time).round(1)

      if success
        puts "Loaded #{@image_name} in #{load_time}s"
        true
      else
        puts "Failed to load #{@image_name}"
        false
      end
    end

    def save
      puts "Saving #{@image_name} to #{@cache_path}..."
      FileUtils.mkdir_p(File.dirname(@cache_path))

      start_time = Time.now
      system("docker save #{@image_name} > #{@cache_path}")
      save_time = (Time.now - start_time).round(1)

      puts "Saved #{@image_name} in #{save_time}s (#{file_size_mb} MB)"
    end

    private

    def file_size_mb
      return 0 unless File.exist?(@cache_path)

      (File.size(@cache_path) / 1024.0 / 1024.0).round(1)
    end
  end
end
