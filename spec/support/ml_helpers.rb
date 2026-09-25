# Conteúdo bruto (string) de uma fixture de spec/fixtures/ml/<nome>.json, pra
# usar em `stub_request(...).to_return(body: ml_fixture("..."))`. Lê direto do
# disco (sem depender do file_fixture_path do rspec-rails, que por padrão
# aponta pra spec/fixtures/files e não pra spec/fixtures/ml).
module MlHelpers
  def ml_fixture(name)
    Rails.root.join("spec/fixtures/ml/#{name}.json").read
  end
end

RSpec.configure do |config|
  config.include MlHelpers
end
