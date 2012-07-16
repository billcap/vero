require 'delayed_job'
require 'vero/jobs/rest_post_job'

module Vero
  module Trackable
    def self.included(base)
      @vero_trackable_map = []
      base.extend(ClassMethods)
    end

    module ClassMethods
      def trackable(*args)
        if @vero_trackable_map.kind_of?(Array)
          @vero_trackable_map = (@vero_trackable_map << args).flatten
        else
          @vero_trackable_map = args
        end
      end

      def trackable_map
        @vero_trackable_map
      end

      def trackable_map_reset!
        @vero_trackable_map = nil
      end
    end

    def to_vero
      result = self.class.trackable_map.inject({}) do |hash, symbol|
        hash[symbol] = self.send(symbol)
        hash
      end

      result[:email] = result.delete(:email_address) if result.has_key?(:email_address)
      result
    end

    def track(event_name, event_data = {}, cta = '')
      validate_configured!
      validate_track_params!(event_name, event_data)

      config = Vero::App.config
      request_params = config.request_params
      request_params.merge!({:event_name => event_name, :identity => self.to_vero, :data => event_data})
      
      method = !config.async ? :post_now : :post_later
      self.send(method, "http://#{config.domain}/api/v1/track.json", request_params)
    end

    private
    def post_now(url, params)
      begin
        job = Vero::Jobs::RestPostJob.new(url, params)
        job.perform
      rescue => e
        Rails.logger.info "Vero: Error attempting to track event: #{params.to_s} error: #{e.message}" if defined? Rails && Rails.logger
      end
    end

    def post_later(url, params)
      job = Vero::Jobs::RestPostJob.new(url, params)

      begin
        ::Delayed::Job.enqueue job
      rescue ActiveRecord::StatementInvalid => e
        if e.message == "Could not find table 'delayed_jobs'"
          raise "To send ratings asynchronously, you must configure delayed_job. Run `rails generate delayed_job:active_record` then `rake db:migrate`."
        else
          raise e
        end
      end
      'success'
    end

    def validate_configured!
      unless Vero::App.configured?
        raise "You must configure the 'vero' gem. Visit https://bitbucket.org/semblance/vero/overview for more details."
      end
    end

    def validate_track_params!(event_name, event_data)
      result = true

      result &&= event_name.kind_of?(String) && !event_name.blank?
      result &&= event_data.nil? || event_data.kind_of?(Hash)

      raise ArgumentError.new({:event_name => event_name, :event_data => event_data}) unless result
    end
  end
end