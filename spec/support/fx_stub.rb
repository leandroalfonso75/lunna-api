# A cotação do dólar (Fx::UsdBrl) vem de fora: nos testes a fonte responde 503 (custos só em US$), a não ser que o teste
# registre outra resposta ou faça stub do .rate.
RSpec.configure do |config|
  config.before do
    Fx::UsdBrl.reset!
    stub_request(:get, Fx::UsdBrl::URL.to_s).to_return(status: 503)
  end
end
