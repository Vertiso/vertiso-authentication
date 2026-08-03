# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Semantic presentation values consumed by authentication components.
    class Theme
      attr_reader :accent,
                  :border,
                  :button,
                  :danger,
                  :field,
                  :focus,
                  :font,
                  :foreground,
                  :muted,
                  :radius,
                  :spacing,
                  :surface

      # @param font [String] typography class values
      # @param foreground [String] primary text class values
      # @param muted [String] secondary text class values
      # @param border [String] border class values
      # @param surface [String] surface class values
      # @param accent [String] accent class values
      # @param danger [String] destructive and error class values
      # @param focus [String] focus-state class values
      # @param spacing [String] container-spacing class values
      # @param radius [String] surface-radius class values
      # @param button [String] primary-button class values
      # @param field [String] input-field class values
      def initialize(
        font:,
        foreground:,
        muted:,
        border:,
        surface:,
        accent:,
        danger:,
        focus:,
        spacing:,
        radius:,
        button:,
        field:
      )
        @accent = accent
        @border = border
        @button = button
        @danger = danger
        @field = field
        @focus = focus
        @font = font
        @foreground = foreground
        @muted = muted
        @radius = radius
        @spacing = spacing
        @surface = surface
      end

      # Returns the neutral engine presentation.
      #
      # @return [Vertiso::Authentication::Theme]
      def self.default
        new(
          font: "font-sans",
          foreground: "text-slate-950",
          muted: "text-slate-600",
          border: "border border-slate-200",
          surface: "bg-white",
          accent: "text-indigo-600",
          danger: "text-red-600",
          focus: "focus:outline-none focus:ring-2 focus:ring-indigo-500",
          spacing: "p-8",
          radius: "rounded-lg",
          button: "bg-slate-950 text-white rounded-lg px-4 py-2.5",
          field: "w-full border border-slate-300 rounded-lg px-4 py-2.5"
        )
      end

      # Returns the production GoalMindr-compatible presentation.
      #
      # @return [Vertiso::Authentication::Theme]
      def self.goalmindr
        new(
          font: "font-sans",
          foreground: "text-gray-900",
          muted: "text-gray-500",
          border: "border border-gray-100",
          surface: "bg-white",
          accent: "text-indigo-600",
          danger: "text-red-600",
          focus: "focus:outline-none focus:ring-2 focus:ring-indigo-500",
          spacing: "p-8",
          radius: "rounded-2xl",
          button: "bg-indigo-600 text-white rounded-xl px-4 py-3",
          field: "w-full border border-gray-300 rounded-xl px-4 py-3 backdrop-blur-sm"
        )
      end

      # Returns the production Vertiso Memory-compatible presentation.
      #
      # @return [Vertiso::Authentication::Theme]
      def self.momento
        new(
          font: "font-poppins",
          foreground: "text-vds-text",
          muted: "text-vds-text-secondary",
          border: "border border-vds-border",
          surface: "bg-vds-black",
          accent: "text-vds-red",
          danger: "text-vds-red",
          focus: "focus:outline-none focus:border-vds-red/60",
          spacing: "p-8",
          radius: "rounded-lg",
          button: "btn-primary",
          field: "w-full bg-vds-surface-2 border border-vds-border rounded-lg px-4 py-2.5"
        )
      end
    end
  end
end
