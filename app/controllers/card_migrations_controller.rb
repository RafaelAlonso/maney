# Fluxo em lote antes de excluir um cartão com gastos: migrar tudo para
# outro cartão ou excluir tudo; ao concluir, o cartão é excluído junto.
class CardMigrationsController < ApplicationController
  before_action :set_card

  def new
    @expense_count = @card.expenses.where(installment_purchase_id: nil).count
    @purchase_count = @card.installment_purchases.count
    @other_cards = Card.where.not(id: @card.id).order(:name)
  end

  def create
    case params[:action_kind]
    when "migrate" then migrate_and_destroy
    when "delete" then delete_and_destroy
    else redirect_to new_card_migration_path(@card), alert: "Escolha o que fazer com os gastos."
    end
  end

  private

  def set_card = @card = Card.find(params[:card_id])

  def migrate_and_destroy
    target = Card.find_by(id: params[:target_card_id])
    if target.nil? || target == @card
      redirect_to new_card_migration_path(@card), alert: "Escolha o cartão de destino." and return
    end
    ActiveRecord::Base.transaction do
      # update_all: reatribuição em massa sem callbacks — as validações dos
      # gastos não mudam (mesmo método, categoria e datas), só o cartão.
      @card.expenses.update_all(card_id: target.id)
      @card.installment_purchases.update_all(card_id: target.id)
      @card.reload.destroy!
    end
    redirect_to cards_path, notice: "Gastos migrados para #{target.name}; cartão #{@card.name} excluído."
  end

  def delete_and_destroy
    name = @card.name
    ActiveRecord::Base.transaction do
      @card.installment_purchases.destroy_all
      @card.expenses.destroy_all
      @card.reload.destroy!
    end
    redirect_to cards_path, notice: "Gastos excluídos junto com o cartão #{name}."
  end
end
