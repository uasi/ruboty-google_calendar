require "active_support/core_ext/date/calculations"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/object/try"
require "google/api_client/client_secrets"
require "google/apis/calendar_v3"
require "ruboty"
require "time"

module Ruboty
  module Handlers
    class GoogleCalendar < Base
      DEFAULT_CALENDAR_ID = "primary"
      DEFAULT_DURATION = 1.day

      env :GOOGLE_CALENDAR_ID, "Google Calendar ID (default: primary)", optional: true
      env :GOOGLE_CLIENT_ID, "Client ID"
      env :GOOGLE_CLIENT_SECRET, "Client Secret"
      env :GOOGLE_REDIRECT_URI, "Redirect URI (http://localhost in most cases)"
      env :GOOGLE_REFRESH_TOKEN, "Refresh token issued with access token"

      on(
        /list events( in (?<minute>\d+) minutes)?\z/,
        description: "List events from Google Calendar",
        name: "list_events",
      )

      def list_events(message)
        event_items = client.list_events(
          calendar_id: calendar_id,
          duration: message[:minute].try(:to_i).try(:minute) || DEFAULT_DURATION,
        ).items
        if event_items.size > 0
          text = event_items.map do |item|
            ItemView.new(item)
          end.join("\n")
          message.reply(text, code: true)
        else
          true
        end
      end

      private

      def calendar_id
        ENV["GOOGLE_CALENDAR_ID"] || DEFAULT_CALENDAR_ID
      end

      def client
        @client ||= Client.new(
          client_id: ENV["GOOGLE_CLIENT_ID"],
          client_secret: ENV["GOOGLE_CLIENT_SECRET"],
          redirect_uri: ENV["GOOGLE_REDIRECT_URI"],
          refresh_token: ENV["GOOGLE_REFRESH_TOKEN"],
        )
      end

      class Client
        APPLICATION_NAME = "ruboty-google_calendar"
        AUTH_URI = "https://accounts.google.com/o/oauth2/auth"
        SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR
        TOKEN_URI = "https://accounts.google.com/o/oauth2/token"

        def initialize(client_id: nil, client_secret: nil, redirect_uri: nil, refresh_token: nil)
          @client_id = client_id
          @client_secret = client_secret
          @redirect_uri = redirect_uri
          @refresh_token = refresh_token
          authenticate!
        end

        # @param [String] calendar_id
        # @param [ActiveSupport::Duration] duration
        # @return [Google::Apis::CalendarV3::Events]
        def list_events(calendar_id: nil, duration: nil)
          calendar_service.list_events(
            calendar_id,
            single_events: true,
            order_by: "startTime",
            time_min: Time.now.iso8601,
            time_max: duration.since.iso8601,
          )
        end

        private

        def calendar_service
          @calendar_service ||= begin
            _calendar_service = Google::Apis::CalendarV3::CalendarService.new
            _calendar_service.client_options.application_name = APPLICATION_NAME
            _calendar_service.client_options.application_version = Ruboty::GoogleCalendar::VERSION
            _calendar_service.authorization = authorization
            _calendar_service.authorization.scope = SCOPE
            _calendar_service
          end
        end

        def authenticate!
          calendar_service.authorization.fetch_access_token!
        end

        def authorization
          client_secrets.to_authorization
        end

        def client_secrets
          Google::APIClient::ClientSecrets.new(
            flow: :installed,
            installed: {
              auth_uri: AUTH_URI,
              client_id: @client_id,
              client_secret: @client_secret,
              redirect_uris: [@redirect_uri],
              refresh_token: @refresh_token,
              token_uri: TOKEN_URI,
            },
          )
        end
      end

      class ItemView
        def initialize(item)
          @item = item
        end

        def to_s
          "#{started_at} - #{finished_at} #{summary}"
        end

        private

        def all_day?
          @item.start.date_time.nil?
        end

        def finished_at
          case
          when all_day?
            "--:--"
          when finished_in_same_day?
            @item.end.date_time.strftime("%H:%M")
          else
            @item.end.date_time.strftime("%Y-%m-%d %H:%M")
          end
        end

        def finished_in_same_day?
          @item.start.date_time.day == @item.end.date_time.day
        end

        def started_at
          if all_day?
            "#{@item.start.date} --:--"
          else
            @item.start.date_time.strftime("%Y-%m-%d %H:%M")
          end
        end

        def summary
          @item.summary
        end
      end
    end
  end
end
