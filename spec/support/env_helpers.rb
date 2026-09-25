# Sem ClimateControl no projeto: stub direto em ENV (`[]` e `fetch`), sempre
# delegando pro valor real quando a chave não foi explicitamente stubada.
# `nil` no value simula variável ausente (ENV.fetch sem default estoura KeyError).
module EnvHelpers
  # Chamadas repetidas no mesmo exemplo acumulam num hash só: reinstalar o stub
  # capturaria o próprio stub como "original" (recursão infinita).
  def stub_env(values)
    first_call = @stubbed_env.nil?
    (@stubbed_env ||= {}).merge!(values.transform_keys(&:to_s))
    return unless first_call

    values = @stubbed_env
    original_bracket = ENV.method(:[])
    original_fetch = ENV.method(:fetch)

    allow(ENV).to receive(:[]) do |key|
      values.key?(key) ? values[key] : original_bracket.call(key)
    end

    allow(ENV).to receive(:fetch) do |key, *args, &blk|
      next original_fetch.call(key, *args, &blk) unless values.key?(key)

      value = values[key]
      next value unless value.nil?
      next args.first if args.any?
      next blk.call(key) if blk

      raise KeyError, "key not found: #{key.inspect}"
    end
  end
end

RSpec.configure do |config|
  config.include EnvHelpers
end
