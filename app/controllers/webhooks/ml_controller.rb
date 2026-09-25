# POST /webhooks/ml (público) → 200 vazio, não processa nada na v1 (SPEC 12).
module Webhooks
  class MlController < ApplicationController
    skip_before_action :authenticate!

    def create
      head :ok
    end
  end
end
