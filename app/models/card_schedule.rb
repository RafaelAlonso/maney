class CardSchedule < ApplicationRecord
  belongs_to :card

  validates :closing_day, :due_day, inclusion: { in: 1..31 }
  validates :valid_from, presence: true, uniqueness: { scope: :card_id }
end
