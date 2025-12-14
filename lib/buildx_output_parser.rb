# frozen_string_literal: true

class BuildxOutputParser
  LAYER_STEP_PATTERN = %r{\[\d+/\d+\]}
  DONE_PATTERN = /DONE\s+(\d+\.?\d*)s/
  CACHED_PATTERN = /CACHED/
  CACHE_IMPORT_PATTERN = /importing cache manifest from/
  EXPORT_IMAGE_PATTERN = /exporting to (docker )?image/
  CACHE_EXPORT_PATTERN = /exporting cache to/

  def parse(output)
    steps = group_by_step_number(output)

    cache_import_seconds = nil
    export_image_seconds = nil
    cache_export_seconds = nil
    cached_layer_count = 0
    built_layer_count = 0
    build_seconds = 0.0

    steps.each_value do |step_content|
      if step_content.match?(CACHE_IMPORT_PATTERN)
        cache_import_seconds = extract_done_time(step_content)
      elsif step_content.match?(CACHE_EXPORT_PATTERN)
        cache_export_seconds = extract_done_time(step_content)
      elsif step_content.match?(EXPORT_IMAGE_PATTERN)
        export_image_seconds = extract_done_time(step_content)
      elsif step_content.match?(LAYER_STEP_PATTERN)
        if step_content.match?(CACHED_PATTERN)
          cached_layer_count += 1
        else
          done_time = extract_done_time(step_content)
          if done_time
            built_layer_count += 1
            build_seconds += done_time
          end
        end
      end
    end

    {
      cache_import_seconds: cache_import_seconds,
      cached_layer_count: cached_layer_count,
      built_layer_count: built_layer_count,
      build_seconds: build_seconds.round(1),
      export_image_seconds: export_image_seconds,
      cache_export_seconds: cache_export_seconds
    }
  end

  private

  def group_by_step_number(output)
    steps = {}
    output.each_line do |line|
      match = line.match(/^#(\d+)\s/)
      next unless match

      step_num = match[1].to_i
      steps[step_num] ||= ''
      steps[step_num] += line
    end
    steps
  end

  def extract_done_time(content)
    match = content.match(DONE_PATTERN)
    return nil unless match

    match[1].to_f
  end
end
