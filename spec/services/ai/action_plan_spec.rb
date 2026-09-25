require "rails_helper"

RSpec.describe Ai::ActionPlan do
  let(:company) { build(:company, :with_ai) }
  let(:prompt) { { system: "prompt do sistema", user: "dados do anúncio" } }
  let(:url) { "https://openrouter.ai/api/v1/chat/completions" }

  before { stub_env("FRONT_URL" => "https://app.lunna.test") }

  def sse_body
    <<~SSE
      : OPENROUTER PROCESSING

      data: {"id":"gen-1","choices":[{"index":0,"delta":{"content":"Diagnóstico: "}}]}

      data: {"id":"gen-1","choices":[{"index":0,"delta":{"content":"tudo certo."}}]}

      data: {"id":"gen-1","choices":[{"index":0,"delta":{}}]}

      data: [DONE]

    SSE
  end

  it "entrega os pedaços de texto na ordem do streaming da OpenRouter" do
    stub_request(:post, url).to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: sse_body)

    chunks = []
    described_class.stream(company, prompt) { |text| chunks << text }

    expect(chunks).to eq([ "Diagnóstico: ", "tudo certo." ])
  end

  it "envia Authorization, o modelo, stream: true e as mensagens system/user" do
    stub_request(:post, url).to_return(status: 200, body: sse_body)

    described_class.stream(company, prompt) { |_text| }

    expect(WebMock).to have_requested(:post, url)
      .with(
        headers: {
          "Authorization" => "Bearer #{company.openrouter_api_key}",
          "HTTP-Referer" => "https://app.lunna.test",
          "X-Title" => "Lunna"
        },
        body: {
          model: company.ai_model,
          stream: true,
          max_tokens: 4096,
          reasoning: { enabled: false },
          messages: [
            { role: "system", content: "prompt do sistema" },
            { role: "user", content: "dados do anúncio" }
          ]
        }
      )
  end

  # Regressão (produção, 2026-09-25): deepseek-v4.1-flash raciocina, manda ~1.100
  # eventos com content "" e termina com finish_reason "length" sem nenhum texto.
  it 'ignora content "" e falha com mensagem clara quando o modelo gastou o limite raciocinando' do
    body = <<~SSE
      data: {"choices":[{"index":0,"delta":{"content":"","reasoning":"pensando"},"finish_reason":null}]}

      data: {"choices":[{"index":0,"delta":{"content":"","reasoning":" mais"},"finish_reason":null}]}

      data: {"choices":[{"index":0,"delta":{"content":""},"finish_reason":"length"}]}

      data: [DONE]

    SSE
    stub_request(:post, url).to_return(status: 200, body: body)

    chunks = []
    expect { described_class.stream(company, prompt) { |text| chunks << text } }
      .to raise_error(Ai::ActionPlan::Error, /gastou todo o limite de tokens raciocinando/)
    expect(chunks).to be_empty
  end

  it "stream ok sem nenhum texto (finish_reason stop) -> erro, nunca plano vazio" do
    body = %(data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n)
    stub_request(:post, url).to_return(status: 200, body: body)

    expect { described_class.stream(company, prompt) { |_text| } }
      .to raise_error(Ai::ActionPlan::Error, "A IA não devolveu o plano. Tente de novo.")
  end

  it "empresa sem chave e sem modelo -> erro de configuração, sem nenhuma requisição" do
    sem_ia = build(:company)

    expect { described_class.stream(sem_ia, prompt) { |_text| } }
      .to raise_error(Ai::ActionPlan::Error, "Configure a chave e o modelo da OpenRouter em Configurações › Empresa.")

    expect(WebMock).not_to have_requested(:post, url)
  end

  it "empresa sem modelo -> erro de configuração, sem nenhuma requisição" do
    sem_modelo = build(:company, openrouter_api_key: "sk-or-v1-chave")

    expect { described_class.stream(sem_modelo, prompt) { |_text| } }
      .to raise_error(Ai::ActionPlan::Error, "Configure a chave e o modelo da OpenRouter em Configurações › Empresa.")

    expect(WebMock).not_to have_requested(:post, url)
  end

  {
    401 => "A OpenRouter recusou a chave. Confira em Configurações › Empresa.",
    403 => "A OpenRouter recusou a chave. Confira em Configurações › Empresa.",
    402 => "Sem créditos na OpenRouter.",
    429 => "Limite de uso atingido, tente em instantes.",
    404 => 'A OpenRouter não aceitou o modelo "anthropic/claude-sonnet-4.5". Confira o nome em Configurações › Empresa.',
    500 => "Não foi possível gerar o plano agora. Tente de novo."
  }.each do |status, message|
    it "HTTP #{status} -> #{message.inspect}" do
      stub_request(:post, url).to_return(status: status, body: { error: { message: "falhou" } }.to_json)

      expect { described_class.stream(company, prompt) { |_text| } }
        .to raise_error(Ai::ActionPlan::Error, message)
    end
  end

  it 'erro no meio do stream (data: com "error") -> mensagem genérica' do
    body = <<~SSE
      data: {"choices":[{"index":0,"delta":{"content":"início"}}]}

      data: {"error":{"message":"algo quebrou"}}

    SSE
    stub_request(:post, url).to_return(status: 200, body: body)

    chunks = []
    expect { described_class.stream(company, prompt) { |text| chunks << text } }
      .to raise_error(Ai::ActionPlan::Error, "Não foi possível gerar o plano agora. Tente de novo.")
    expect(chunks).to eq([ "início" ])
  end

  it "erro de conexão/timeout -> mensagem genérica" do
    stub_request(:post, url).to_timeout

    expect { described_class.stream(company, prompt) { |_text| } }
      .to raise_error(Ai::ActionPlan::Error, "Não foi possível gerar o plano agora. Tente de novo.")
  end
end
