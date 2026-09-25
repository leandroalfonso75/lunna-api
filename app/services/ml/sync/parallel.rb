# HTTP paralelo com Thread puro (DECISOES §6) — usado só dentro das etapas
# de sincronização, e só para chamadas ao ML; TODA gravação no banco
# acontece depois, no thread principal, a partir do array devolvido aqui.
#
# `map` devolve os resultados na MESMA ORDEM de `list`, um por item:
# [:ok, valor] ou [:error, exception] (uma exceção de item nunca derruba os
# outros). Cada thread roda dentro de `Rails.application.executor.wrap`
# (autoload thread-safe); o `join` roda dentro de
# `ActiveSupport::Dependencies.interlock.permit_concurrent_loads` pra não
# travar em dead-lock com o autoloader do thread principal.
module Ml
  module Sync
    module Parallel
      def self.map(list, threads:)
        results = Array.new(list.size)

        jobs = list.each_with_index.group_by { |_item, i| i % threads }.values.map do |pairs|
          Thread.new do
            Rails.application.executor.wrap do
              pairs.each do |item, i|
                results[i] = begin
                  [ :ok, yield(item) ]
                rescue => e
                  [ :error, e ]
                end
              end
            end
          end
        end

        ActiveSupport::Dependencies.interlock.permit_concurrent_loads { jobs.each(&:join) }

        results
      end
    end
  end
end
