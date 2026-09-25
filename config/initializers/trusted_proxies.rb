# Be sure to restart your server when you modify this file.
#
# Em produção a API roda atrás de um ingress; sem confiar nele explicitamente,
# `request.remote_ip` (e o rate_limit nativo, que usa o IP para a chave) pode
# aceitar um `X-Forwarded-For` forjado como se fosse o cliente real. Os
# defaults do Rails (loopback + faixas privadas) já cobrem o pod do ingress
# dentro do cluster; `TRUSTED_PROXIES` (env, opcional, vírgula-separado) soma
# CIDRs extras (ex.: um WAF/CDN na frente) sem exigir deploy de código.
extra_proxies = ENV.fetch("TRUSTED_PROXIES", "").split(",").map(&:strip).reject(&:blank?)

Rails.application.config.action_dispatch.trusted_proxies = (
  ActionDispatch::RemoteIp::TRUSTED_PROXIES + extra_proxies.map { |cidr| IPAddr.new(cidr) }
)
