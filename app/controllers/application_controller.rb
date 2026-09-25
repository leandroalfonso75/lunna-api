class ApplicationController < ActionController::API
  include ErrorRendering
  include Authentication
  include Payloads
end
