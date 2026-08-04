class Card < ApplicationRecord
  has_many :card_schedules, dependent: :destroy
  has_many :expenses, dependent: :restrict_with_error
  has_many :installment_purchases, dependent: :restrict_with_error

  validates :name, presence: true

  # Archived means "I no longer spend on this card" — not settled, not deleted.
  # Deliberately NOT a default_scope: an archived card's statements, totals and
  # charts must keep counting everywhere, and the only place it disappears from
  # is the picker for a NEW expense (ApplicationHelper#card_options_for). A
  # default scope would quietly take it out of all of them instead.
  scope :active, -> { where(archived_at: nil) }

  def archived? = archived_at.present?
  def archive! = update!(archived_at: Time.current)
  def reactivate! = update!(archived_at: nil)

  # Editing the days never rewrites the old validity window: it creates a new
  # one effective from the start of the window open today — already-closed
  # statements stay derived from the old one, and the boundary is always a real
  # closing date (see Budgeting::StatementAttribution.window_start). Returns nil
  # if the requested days are already the current ones.
  #
  # The returned row is usually new, but it can come back persisted: when the
  # boundary coincides with a validity window that already exists (a second
  # correction within the same window, or a card whose timeline starts in the
  # future), the existing row itself comes back dirty. The caller always saves —
  # never branch on `persisted?` / `new_record?`.
  def reschedule(closing_day:, due_day:, today: Date.current)
    wanted = [closing_day.to_i, due_day.to_i]
    current = Budgeting::Schedule.for(card: self, date: today)
    return nil if [current.closing_day, current.due_day] == wanted

    row = card_schedules.find_or_initialize_by(valid_from: schedule_start_on(today))
    row.assign_attributes(closing_day: wanted[0], due_day: wanted[1])
    row
  end

  private

  # The clamp does NOT protect the window boundary — window_start is what
  # guarantees that, returning the start of the open window by definition. It
  # only guarantees ordering: a new validity window never precedes an existing
  # one. It's a backstop against rows written outside here (a console fix, a
  # data migration, a spec building card_schedules by hand) that might sit on
  # dates that are no window boundary at all.
  def schedule_start_on(today)
    boundary = Budgeting::StatementAttribution.window_start(card: self, date: today)
    # maximum is never nil here: Schedule.for would have raised without a validity window.
    [boundary, card_schedules.maximum(:valid_from)].max
  end
end
