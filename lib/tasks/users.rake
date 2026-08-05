require "io/console"

namespace :users do
  desc "Create the first person and attach every existing row to them (one-shot)"
  task claim: :environment do
    read_secret = lambda do |label|
      print label
      secret = $stdin.noecho(&:gets).to_s.chomp
      puts
      secret
    end

    print "E-mail: "
    email_address = $stdin.gets.to_s.strip
    password = read_secret.call("Senha: ")
    confirmation = read_secret.call("Repita a senha: ")

    abort "As senhas não conferem." unless password == confirmation
    abort "A senha precisa de pelo menos 8 caracteres." if password.length < 8

    begin
      result = Users::Claim.new(email_address:, password:).call
    rescue Users::Claim::AlreadyClaimed
      abort "Já existe uma pessoa cadastrada — nada a fazer."
    rescue Users::Claim::Tampered => error
      abort "Migração abortada: #{error.message}"
    end

    puts "Pronto: #{result.rows_attached} linhas atribuídas a #{result.user.email_address}."
  end
end
