class Admin::BaseController < ApplicationController
  http_basic_authenticate_with(
    name: ENV.fetch("ROGUE_ADMIN_USERNAME"),
    password: ENV.fetch("ROGUE_ADMIN_PASSWORD")
  )
end
