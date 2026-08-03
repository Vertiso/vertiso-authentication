# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Stores optional metadata about a principal's database-backed authentication session.
    class AuthenticationSession < ::ApplicationRecord
      belongs_to :principal, polymorphic: true, optional: true

      scope :active_at, lambda { |time|
        where("expires_at IS NULL OR expires_at > ?", time)
      }
      scope :inactive_at, ->(time) { where(expires_at: ..time) }
      scope :active, -> { active_at(Time.current) }
      scope :inactive, -> { inactive_at(Time.current) }

      # Returns whether the session is active at a specific time.
      #
      # @param time [Time]
      # @return [Boolean]
      def active_at?(time)
        expires_at.nil? || expires_at > time
      end

      # Returns whether the session is active now.
      #
      # @return [Boolean]
      def active?
        active_at?(Time.current)
      end

      # Updates the session's most recent activity time.
      #
      # @return [Boolean]
      def touch_activity!
        update!(last_activity_at: Time.current)
      end
    end
  end
end
