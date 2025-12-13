# frozen_string_literal: true

require_relative '../lib/buildx_output_parser'

RSpec.describe BuildxOutputParser do
  describe '#parse' do
    let!(:parser) { BuildxOutputParser.new }

    context 'with typical buildx output' do
      let!(:output) do
        <<~OUTPUT
          #1 [internal] load build definition from Dockerfile
          #1 transferring dockerfile: 527B done
          #1 DONE 0.0s

          #2 [internal] load metadata for docker.io/library/ruby:3.2.2
          #2 DONE 0.3s

          #3 [internal] load .dockerignore
          #3 transferring context: 2B done
          #3 DONE 0.0s

          #4 importing cache manifest from registry.saturnci.com:5000/myproject:cache
          #4 DONE 1.2s

          #5 [1/5] FROM docker.io/library/ruby:3.2.2@sha256:abc123
          #5 CACHED

          #6 [2/5] WORKDIR /app
          #6 CACHED

          #7 [3/5] COPY Gemfile Gemfile.lock ./
          #7 DONE 0.1s

          #8 [4/5] RUN bundle install
          #8 0.543 Fetching gem metadata...
          #8 12.34 Bundle complete!
          #8 DONE 15.2s

          #9 [5/5] COPY . .
          #9 DONE 0.8s

          #10 exporting to image
          #10 exporting layers
          #10 exporting layers 2.1s done
          #10 writing image sha256:def456
          #10 naming to docker.io/library/myimage:latest
          #10 DONE 2.5s

          #11 exporting cache to registry.saturnci.com:5000/myproject:cache
          #11 preparing build cache for export
          #11 writing layer sha256:aaa111
          #11 writing layer sha256:bbb222
          #11 DONE 3.4s
        OUTPUT
      end

      let!(:result) { parser.parse(output) }

      it 'extracts the cache import time' do
        expect(result[:cache_import_seconds]).to eq(1.2)
      end

      it 'counts the number of cached layers' do
        expect(result[:cached_layer_count]).to eq(2)
      end

      it 'counts the number of built layers' do
        expect(result[:built_layer_count]).to eq(3)
      end

      it 'extracts total build time for non-cached layers' do
        expect(result[:build_seconds]).to eq(16.1)
      end

      it 'extracts the export to image time' do
        expect(result[:export_image_seconds]).to eq(2.5)
      end

      it 'extracts the cache export time' do
        expect(result[:cache_export_seconds]).to eq(3.4)
      end
    end

    context 'with no cache import' do
      let!(:output) do
        <<~OUTPUT
          #1 [internal] load build definition from Dockerfile
          #1 DONE 0.0s

          #2 [1/2] FROM docker.io/library/ruby:3.2.2
          #2 DONE 5.0s

          #3 [2/2] RUN echo hello
          #3 DONE 0.5s

          #4 exporting to image
          #4 DONE 1.0s
        OUTPUT
      end

      let!(:result) { parser.parse(output) }

      it 'returns nil for cache import time' do
        expect(result[:cache_import_seconds]).to be_nil
      end

      it 'returns zero cached layers' do
        expect(result[:cached_layer_count]).to eq(0)
      end

      it 'counts the built layers' do
        expect(result[:built_layer_count]).to eq(2)
      end
    end

    context 'with all layers cached' do
      let!(:output) do
        <<~OUTPUT
          #1 [internal] load build definition from Dockerfile
          #1 DONE 0.0s

          #2 importing cache manifest from registry.saturnci.com:5000/myproject:cache
          #2 DONE 0.8s

          #3 [1/3] FROM docker.io/library/ruby:3.2.2
          #3 CACHED

          #4 [2/3] WORKDIR /app
          #4 CACHED

          #5 [3/3] RUN bundle install
          #5 CACHED

          #6 exporting to image
          #6 DONE 0.2s
        OUTPUT
      end

      let!(:result) { parser.parse(output) }

      it 'returns zero build time' do
        expect(result[:build_seconds]).to eq(0.0)
      end

      it 'counts all layers as cached' do
        expect(result[:cached_layer_count]).to eq(3)
      end

      it 'returns zero built layers' do
        expect(result[:built_layer_count]).to eq(0)
      end
    end

    context 'with empty output' do
      let!(:output) { '' }
      let!(:result) { parser.parse(output) }

      it 'returns zeros for all numeric fields' do
        expect(result[:cache_import_seconds]).to be_nil
        expect(result[:cached_layer_count]).to eq(0)
        expect(result[:built_layer_count]).to eq(0)
        expect(result[:build_seconds]).to eq(0.0)
        expect(result[:export_image_seconds]).to be_nil
        expect(result[:cache_export_seconds]).to be_nil
      end
    end
  end
end
