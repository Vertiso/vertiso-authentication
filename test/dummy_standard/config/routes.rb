# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

Rails.application.routes.draw do
  root to: "application#signed_in"

  mount Vertiso::Authentication::Engine => "/authentication",
                                           as: "vertiso_authentication"

  get "/authentication-state",
      to: "application#authentication_state",
      as: :authentication_state
  get "/seed-session", to: "application#seed_session", as: :seed_session
  delete "/session-token",
         to: "application#clear_session_token",
         as: :clear_session_token
  get "/resume", to: "application#remember_location", as: :remember_location
  get "/signed-in", to: "application#signed_in", as: :signed_in
  get "/registered", to: "application#registered", as: :registered
  get "/confirmation-required",
      to: "application#signed_in",
      as: :confirmation_required
  get "/confirmed", to: "application#signed_in", as: :confirmed
end
