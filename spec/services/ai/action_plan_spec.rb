require "rails_helper"

RSpec.describe Ai::ActionPlan do
  # O cliente é memoizado globalmente (@client, DECISOES/A5) — precisa
  # resetar entre exemplos pra não vazar a chave/stub de um teste pro outro.
  before { described_class.instance_variable_set(:@client, nil) }
  after { described_class.instance_variable_set(:@client, nil) }

  let(:prompt) { { system: "prompt do sistema", user: "dados do anúncio" } }

  def sse_body
    <<~SSE
      event: message_start
      data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-opus-5","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}

      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Olá, mundo"}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"!"}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":0}

      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":5}}

      event: message_stop
      data: {"type":"message_stop"}

    SSE
  end

  it "entrega os pedaços de texto do streaming da Claude API" do
    stub_env("ANTHROPIC_API_KEY" => "fake-key")
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: sse_body)

    chunks = []
    described_class.stream(prompt) { |text| chunks << text }

    expect(chunks.join).to eq("Olá, mundo!")
  end

  it "sem ANTHROPIC_API_KEY -> erro de configuração" do
    stub_env("ANTHROPIC_API_KEY" => nil)

    expect { described_class.stream(prompt) { |_text| } }
      .to raise_error(Ai::ActionPlan::Error, "Integração com a IA não configurada.")
  end

  it "429 da Claude API -> mensagem de limite de uso" do
    stub_env("ANTHROPIC_API_KEY" => "fake-key")
    stub_request(:post, "https://api.anthropic.com/v1/messages").to_return(
      status: 429,
      headers: { "Content-Type" => "application/json" },
      body: { type: "error", error: { type: "rate_limit_error", message: "limited" } }.to_json
    )

    expect { described_class.stream(prompt) { |_text| } }
      .to raise_error(Ai::ActionPlan::Error, "Limite de uso atingido, tente em instantes.")
  end
end
