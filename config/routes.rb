# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

Vertiso::Authentication::Engine.routes.draw do
  get "/login", to: "sessions#new", as: :login
  post "/login", to: "sessions#create", as: :session
  delete "/logout", to: "sessions#destroy", as: :logout

  get "/register", to: "registrations#new", as: :new_registration
  post "/register", to: "registrations#create", as: :registration
end
