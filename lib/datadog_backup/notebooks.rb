# frozen_string_literal: true

module DatadogBackup
  # Notebook specific overrides for backup and restore.
  class Notebooks < Resources
    def all
      get_all
    end

    def backup
      LOGGER.info("Starting diffs on #{::DatadogBackup::ThreadPool::TPOOL.max_length} threads")
      futures = all.map do |notebook|
        Concurrent::Promises.future_on(::DatadogBackup::ThreadPool::TPOOL, notebook) do |book|
          id = book[id_keyname]
          get_and_write_file(id)
        end
      end

      watcher = ::DatadogBackup::ThreadPool.watcher
      watcher.join if watcher.status

      Concurrent::Promises.zip(*futures).value!
    end

    def get_by_id(id)
      begin
        notebook = except(get(id))
      rescue Faraday::ResourceNotFound => e
        notebook = {}
      end
      except(notebook)
    end

    def initialize(options)
      super(options)
      @banlist = [].freeze
    end

    def create(body)
      headers = {}
      response = api_service.post(
        "/api/#{api_version}/#{api_resource_name}",
        json_api_payload(body, include_id: false),
        headers
      )
      resbody = body_with_2xx(response)
      LOGGER.warn "Successfully created #{resbody.fetch(id_keyname)} in datadog."
      LOGGER.info 'Invalidating cache'
      @get_all = nil
      resbody
    end

    def update(id, body)
      headers = {}
      response = api_service.put(
        "/api/#{api_version}/#{api_resource_name}/#{id}",
        json_api_payload(body, include_id: true),
        headers
      )
      resbody = body_with_2xx(response)
      LOGGER.warn "Successfully restored #{id} to datadog."
      LOGGER.info 'Invalidating cache'
      @get_all = nil
      resbody
    end

    private

    def api_version
      'v1'
    end

    def api_resource_name
      'notebooks'
    end

    def id_keyname
      'id'
    end

    def body_with_2xx(response)
      super(response).fetch('data')
    end

    def json_api_payload(body, include_id:)
      data = {
        'type' => body.fetch('type', 'notebooks'),
        'attributes' => body.fetch('attributes', {})
      }

      data['relationships'] = body['relationships'] if body.key?('relationships')
      data['id'] = body['id'] if include_id && body.key?('id')

      { 'data' => data }
    end
  end
end
