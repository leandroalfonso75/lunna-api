namespace :olist do
  desc "Mostra a URL para autorizar o Olist ERP da empresa de um admin: bin/rails 'olist:conectar[email]'"
  task :conectar, [ :email ] => :environment do |_task, args|
    abort "Informe o e-mail de um admin: bin/rails 'olist:conectar[email@exemplo.com]'" if args[:email].blank?
    abort "Defina OLIST_CLIENT_ID e OLIST_CLIENT_SECRET no .env." unless Olist::OAuth.configured?

    user = User.find_by(email: args[:email])
    abort "Usuário não encontrado." if user.nil?
    abort "O usuário precisa ser admin." unless user.admin?

    OlistOauthState.expired.delete_all
    state = OlistOauthState.create!(state: SecureRandom.uuid, company: user.company, user: user)

    puts "Abra esta URL no navegador, logado no Olist ERP, e autorize (vale por 1 hora):"
    puts Olist::OAuth.authorize_url(state.state)
  end

  desc "Mostra o estado da conexão do Olist ERP de cada empresa"
  task status: :environment do
    OlistConnection.includes(:company).find_each do |c|
      puts "#{c.company.name}: #{c.status} (acesso até #{c.expires_at}, renovação até #{c.refresh_expires_at})"
    end
    puts "Nenhuma conexão." if OlistConnection.none?
  end
end
