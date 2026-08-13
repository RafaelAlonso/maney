require "io/console"

namespace :users do
  desc "Cria a primeira pessoa e anexa a ela todas as linhas existentes (roda uma única vez). " \
       "Rode isto ANTES de criar qualquer pessoa por outro caminho (ex.: `rails console`): se já existir " \
       "mais de uma pessoa, ou uma pessoa que já tem dados seus, este comando se recusa a rodar e não há " \
       "como desfazer isso pelo app."
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

  desc "Apaga em definitivo as contas excluídas há mais de 30 dias. " \
       "Roda toda noite; não há como desfazer."
  task purge: :environment do
    purged = User.purgeable.to_a

    purged.each do |user|
      Users::Purge.new(user).call
      puts "Conta apagada em definitivo: #{user.email_address}"
    rescue => error
      # One person's row failing to purge must not take the rest of the night's
      # batch down with it — log and move on to the next purgeable account.
      puts "Falha ao apagar #{user.email_address}: #{error.message}"
    end

    puts "Nada a apagar." if purged.empty?
  end
end
