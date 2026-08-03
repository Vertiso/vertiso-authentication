# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

Vertiso::Authentication::Engine.routes.draw do
  get "/login", to: "sessions#new", as: :login
  post "/login", to: "sessions#create", as: :session
  delete "/logout", to: "sessions#destroy", as: :logout

  get "/auth/:provider/callback",
      to: "sessions#create_by_oauth",
      as: :oauth_callback
  get "/auth/failure", to: "sessions#oauth_failure", as: :oauth_failure
  get "/auth/email",
      to: "sessions#prompt_email",
      as: :prompt_oauth_email
  post "/auth/email",
       to: "sessions#complete_email_signup",
       as: :complete_oauth_email
  delete "/auth/oauth-accounts/:id",
         to: "oauth_accounts#destroy",
         as: :oauth_account

  get "/register", to: "registrations#new", as: :new_registration
  post "/register", to: "registrations#create", as: :registration

  get "/confirm-email/:token",
      to: "confirmations#show",
      as: :confirm_email
  post "/confirm-email",
       to: "confirmations#create",
       as: :resend_confirmation

  get "/forgot-password",
      to: "password_resets#new",
      as: :forgot_password
  post "/forgot-password", to: "password_resets#create"
  get "/reset-password/:token",
      to: "password_resets#edit",
      as: :reset_password
  patch "/reset-password/:token", to: "password_resets#update"
end
