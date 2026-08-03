# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

# Minimal mapped-host controller used to exercise the engine through requests.
class ApplicationController < ActionController::Base
  include Vertiso::Authentication::BrowserAuthentication if defined?(
    Vertiso::Authentication::BrowserAuthentication
  )

  # Returns the host-visible browser-authentication state.
  #
  # @return [void]
  def authentication_state
    render json: {
      principal_id: current_principal&.id,
      remember_token: session[:remember_token],
      session_identifier: authentication_session_identifier,
      stale_marker: session[:stale_marker],
      forward_to_url: session[:forward_to_url]
    }
  end

  # Seeds state that must be rotated or preserved by a login.
  #
  # @return [void]
  def seed_session
    session[:stale_marker] = "stale"
    session[:forward_to_url] = params[:forward_to_url] if params[:forward_to_url]
    render json: { session_identifier: authentication_session_identifier }
  end

  # Removes only the Rails-session token, leaving the encrypted cookie intact.
  #
  # @return [void]
  def clear_session_token
    session.delete(:remember_token)
    head :no_content
  end

  # Stores a real request URL before handing control to the engine login.
  #
  # @return [void]
  def remember_location
    store_location
    redirect_to vertiso_authentication.login_path
  end

  # Provides a host-owned successful-authentication destination.
  #
  # @return [void]
  def signed_in
    head :ok
  end

  # Provides a host-owned successful-registration destination.
  #
  # @return [void]
  def registered
    head :ok
  end
end
