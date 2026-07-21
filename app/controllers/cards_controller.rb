class CardsController < ApplicationController
  before_action :set_card, only: %i[edit update destroy]

  def index
    @cards = Card.order(:name)
  end

  def new
    @card = Card.new
    @days = {}
  end

  def create
    @card = Card.new(name: card_params[:name])
    schedule = @card.card_schedules.build(closing_day: card_params[:closing_day], due_day: card_params[:due_day],
                                          valid_from: Setting.instance.first_month)
    if @card.save
      redirect_to cards_path, notice: "Cartão cadastrado."
    else
      # `@card.save` invalida o schedule filho como efeito colateral do
      # autosave e só deixa em @card.errors o genérico "Card schedules is
      # invalid" — a mensagem específica ("Closing day is not included in
      # the list") fica isolada em `schedule.errors`. Mescla para o usuário
      # ver a causa e descarta o genérico, que não agrega nada depois disso.
      @card.errors.merge!(schedule.errors)
      @card.errors.delete(:card_schedules)
      @days = card_params.slice(:closing_day, :due_day)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    schedule = Budgeting::Schedule.for(card: @card, date: Date.current)
    @days = { closing_day: schedule.closing_day, due_day: schedule.due_day }
  end

  def update
    @card.name = card_params[:name]
    schedule = @card.reschedule(closing_day: card_params[:closing_day], due_day: card_params[:due_day])
    # Não usa `[@card, *schedule].all?(&:valid?)`: `Enumerable#all?`
    # short-circuita, então se @card já for inválido `schedule.valid?` nunca
    # roda. Isso passa despercebido quando `schedule` é uma linha nova (o
    # autosave de `@card.valid?` valida os filhos não salvos como efeito
    # colateral), mas `reschedule` pode devolver uma linha já persistida e
    # suja (ver Card#reschedule) — para essa, autosave não valida sem
    # `autosave: true`. Chama os dois `valid?` sempre, sem depender de
    # short-circuit nem desse efeito colateral.
    card_valid = @card.valid?
    schedule_valid = schedule.nil? || schedule.valid?
    if card_valid && schedule_valid
      ActiveRecord::Base.transaction { @card.save!; schedule&.save! }
      redirect_to cards_path, notice: "Cartão atualizado."
    else
      @card.errors.merge!(schedule.errors) if schedule
      # `reschedule` pode ter sujado uma linha dentro da associação
      # `card_schedules` já carregada; recarrega para o form e a lista não
      # mostrarem dias que não foram de fato salvos.
      @card.reload
      @card.name = card_params[:name]
      @days = card_params.slice(:closing_day, :due_day)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @card.expenses.exists? || @card.installment_purchases.exists?
      redirect_to new_card_migration_path(@card)
    elsif @card.destroy
      redirect_to cards_path, notice: "Cartão excluído."
    else
      # Hoje inatingível através do guard acima (que é completo contra o
      # modelo atual), mas `dependent: :restrict_with_error` faz `destroy`
      # devolver `false` em vez de levantar — sem este ramo, uma falha real
      # anunciaria sucesso enquanto o registro continua existindo.
      redirect_to cards_path, alert: @card.errors.full_messages.to_sentence
    end
  end

  private

  def set_card = @card = Card.find(params[:id])

  def card_params = params.require(:card).permit(:name, :closing_day, :due_day)
end
