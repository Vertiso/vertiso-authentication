# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

Vertiso::Authentication::Engine.routes.draw do
  get "/login", to: "sessions#new", as: :login
  post "/login", to: "sessions#create", as: :session
  delete "/logout", to: "sessions#destroy", as: :logout

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
