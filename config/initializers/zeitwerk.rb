# app/services/ml/oauth.rb define Ml::OAuth. Só o autoloader aprende o acrônimo:
# um `inflect.acronym` global mudaria também MlOauthState/ml_oauth_states.
Rails.autoloaders.each { |loader| loader.inflector.inflect("oauth" => "OAuth") }
