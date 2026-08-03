# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

# Mapped host principal used by engine compatibility tests.
class User < ApplicationRecord
  include Vertiso::Authentication::Authenticatable
end
