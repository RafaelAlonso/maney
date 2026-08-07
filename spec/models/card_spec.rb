require "rails_helper"

RSpec.describe Card do
  it "requires a name" do
    expect(Card.new(name: "")).not_to be_valid
    expect(Card.new(name: "Azul")).to be_valid
  end

  describe "#reschedule" do
    include ActiveSupport::Testing::TimeHelpers

    let(:today) { Date.new(2026, 7, 21) } # Tuesday, within the window [03/07, 05/08)

    # Azul: closes 5, due 12, first validity window on 01/03/2026 (first_month).
    let(:card) do
      create_setting!(first_month: Date.new(2026, 3, 1))
      create_card!
    end

    def statement_for(date)
      Budgeting::StatementAttribution.statement_for(card:, date:)
    end

    def schedule_on(date)
      Budgeting::Schedule.for(card:, date:)
    end

    # The rule that gives the task meaning: every validity window other than the
    # first starts on a real effective closing. Written as a loop so it keeps
    # holding when future tasks add rows.
    def expect_every_schedule_on_a_real_boundary
      rows = card.card_schedules.reload.order(:valid_from).to_a
      rows.drop(1).each do |row|
        expect(statement_for(row.valid_from - 1).effective_closing).to eq(row.valid_from),
                                                                      "validity window of #{row.valid_from} doesn't start on a statement's effective closing"
      end
    end

    it "returns nil when the requested days are already the current ones" do
      expect(card.reschedule(closing_day: 5, due_day: 12, today:)).to be_nil
    end

    it "places the new validity window at the start of the open window (03/07), not on today" do
      row = card.reschedule(closing_day: 20, due_day: 27, today:)

      expect(row.valid_from).to eq(Date.new(2026, 7, 3))
      expect(row.valid_from).not_to eq(today) # the bug this task exists to kill
      expect(row.closing_day).to eq(20)
      expect(row.due_day).to eq(27)
    end

    it "saves nothing — the caller validates and saves in its own transaction" do
      expect(card.reschedule(closing_day: 20, due_day: 27, today:)).not_to be_persisted
      expect { card.reschedule(closing_day: 20, due_day: 27, today:) }
        .not_to change { CardSchedule.count }
    end

    # Counterpoint to the example above: `persisted?` isn't a contract. With the
    # timeline starting in the future (today before the first validity window)
    # the boundary is the initial date itself, so the ALREADY-persisted initial
    # row comes back dirty. The caller saves it just the same.
    it "timeline in the future: returns the already-persisted initial validity window, with the new days" do
      row = card.reschedule(closing_day: 20, due_day: 27, today: Date.new(2026, 2, 10))

      expect(row).to be_persisted
      expect(row).to eq(card.card_schedules.first)
      expect(row.valid_from).to eq(Date.new(2026, 3, 1))
      expect(row.closing_day).to eq(20)
      expect(row.due_day).to eq(27)

      row.save!
      expect(card.card_schedules.reload.count).to eq(1)
      expect(schedule_on(Date.new(2026, 3, 10)).closing_day).to eq(20)
    end

    it "after saving: old validity window intact, new one in effect from the open window on" do
      card.reschedule(closing_day: 20, due_day: 27, today:).save!

      expect(schedule_on(Date.new(2026, 3, 10)).closing_day).to eq(5)  # closed statement, intact
      expect(schedule_on(today).closing_day).to eq(20)
      expect(schedule_on(today).due_day).to eq(27)
      expect(card.card_schedules.count).to eq(2)
    end

    it "two corrections on the same day amend the same row instead of stacking another" do
      travel_to(Time.zone.local(2026, 7, 21, 10, 0, 0)) do
        # Days 28/27: still upcoming within the open window, so the first
        # correction closes no statement and the boundary stays at 03/07.
        card.reschedule(closing_day: 28, due_day: 10).save!
        card.reschedule(closing_day: 27, due_day: 10).save!

        expect(card.card_schedules.reload.count).to eq(2)
        expect(card.card_schedules.maximum(:valid_from)).to eq(Date.new(2026, 7, 3))
        expect(schedule_on(Date.current).closing_day).to eq(27)
        expect(schedule_on(Date.current).due_day).to eq(10)
        expect(schedule_on(Date.new(2026, 3, 10)).closing_day).to eq(5)
      end
    end

    # Counterpoint: when the first correction adopts a closing day the open
    # window has ALREADY passed, it closes a statement right away (window
    # [03/07, 20/07), closed on 20/07 — yesterday). The second correction on the
    # same day lands in a new window and so stacks a row: amending the 03/07 one
    # would reopen an already-closed statement. Not amending here is the correct
    # behavior, not a regression of "two corrections on the same day".
    it "a second correction on the same day stacks a row when the first closed a statement right away" do
      travel_to(Time.zone.local(2026, 7, 21, 10, 0, 0)) do
        card.reschedule(closing_day: 20, due_day: 27).save!
        expect(statement_for(Date.current).effective_closing).to eq(Date.new(2026, 8, 20))
        expect(statement_for(Date.new(2026, 7, 19)).closed?(today: Date.current)).to be(true)

        card.reschedule(closing_day: 21, due_day: 27).save!

        rows = card.card_schedules.reload.order(:valid_from).map { [ _1.valid_from, _1.closing_day, _1.due_day ] }
        expect(rows).to eq([
                             [ Date.new(2026, 3, 1), 5, 12 ],
                             [ Date.new(2026, 7, 3), 20, 27 ],
                             [ Date.new(2026, 7, 20), 21, 27 ]
                           ])
        expect(schedule_on(Date.current).closing_day).to eq(21)
        expect(schedule_on(Date.new(2026, 3, 10)).closing_day).to eq(5)
        expect_every_schedule_on_a_real_boundary
      end
    end

    # A card that closes 31: in February/2026 the closing overflows to 03/03
    # (Tuesday). The first edit is born on that boundary with day 1, and then
    # succ starts resolving the validity window ON 03/03 — cycle 03 closes
    # nominally on 01/03 (Sunday), effective 27/02. The chain MOVES BACK, and the
    # computed boundary would front-run a validity window that already exists.
    context "when the validity-window swap makes the statement chain move backward" do
      let(:card) { create_card(name: "Trinta e um", closing_day: 31, due_day: 10, valid_from: Date.new(2026, 1, 1)) }

      it "never places the new validity window before an existing one" do
        card.reschedule(closing_day: 1, due_day: 10, today: Date.new(2026, 3, 10)).save!
        expect(card.card_schedules.reload.maximum(:valid_from)).to eq(Date.new(2026, 3, 3))

        row = card.reschedule(closing_day: 15, due_day: 20, today: Date.new(2026, 3, 20))

        expect(row.valid_from).to be >= card.card_schedules.maximum(:valid_from),
                                  "new validity window at #{row.valid_from} precedes the existing one at #{card.card_schedules.maximum(:valid_from)}"
        expect(row.valid_from).to eq(Date.new(2026, 3, 3)) # amends the boundary row, doesn't stack another
        row.save!

        expect(card.card_schedules.reload.count).to eq(2)
        expect_every_schedule_on_a_real_boundary
      end

      # Months later, the open window's boundary left 03/03 long ago. A traversal
      # with succ, however, stops at the March dive and returns 03/03 forever:
      # the June edit would rewrite the middle row, deleting a validity window and
      # reassigning three already-closed statements.
      it "an edit months later opens a new validity window in the open window, without rewriting the middle one" do
        card.reschedule(closing_day: 1, due_day: 10, today: Date.new(2026, 3, 10)).save!
        expect(card.card_schedules.reload.maximum(:valid_from)).to eq(Date.new(2026, 3, 3))

        row = card.reschedule(closing_day: 15, due_day: 20, today: Date.new(2026, 6, 15))

        expect(row.valid_from).to eq(Date.new(2026, 6, 1)),
                                  "new validity window at #{row.valid_from}: went retroactive over already-closed statements"
        row.save!

        rows = card.card_schedules.reload.order(:valid_from).map { [ _1.valid_from, _1.closing_day, _1.due_day ] }
        expect(rows).to eq([
                             [ Date.new(2026, 1, 1), 31, 10 ],
                             [ Date.new(2026, 3, 3), 1, 10 ],
                             [ Date.new(2026, 6, 1), 15, 20 ]
                           ])
        expect_every_schedule_on_a_real_boundary
      end
    end

    it "invariant: every validity window after the first starts on a real effective closing" do
      expect_every_schedule_on_a_real_boundary # single row: nothing to check, but the loop runs

      card.reschedule(closing_day: 20, due_day: 27, today:).save!

      expect(card.card_schedules.count).to eq(2)
      expect_every_schedule_on_a_real_boundary
    end
  end

  describe "archiving" do
    # No `create_setting!` here: `create_card!` already falls back to
    # 01/03/2026 without one, and Setting is a singleton (`single_row`), so an
    # extra row would fight any sibling example that creates its own.
    it "keeps archived cards out of .active and brings them back on reactivate" do
      kept = create_card!(name: "Azul")
      retired = create_card!(name: "Preto")

      retired.archive!

      expect(Card.active).to contain_exactly(kept)
      expect(retired).to be_archived

      retired.reactivate!

      expect(Card.active).to contain_exactly(kept, retired)
      expect(retired).not_to be_archived
    end

    # The story's "archiving and reactivating in quick succession" edge case: the
    # round trip is a no-op on everything except the flag. The schedules matter
    # most — they are what every past statement is still derived from.
    it "changes nothing but the flag on an archive/reactivate round trip" do
      card = create_card!(name: "Azul", closing_day: 5, due_day: 12)
      before = [ card.name, card.card_schedules.pluck(:closing_day, :due_day, :valid_from) ]

      card.archive!
      card.reactivate!
      card.reload

      expect([ card.name, card.card_schedules.pluck(:closing_day, :due_day, :valid_from) ]).to eq before
      expect(card.archived_at).to be_nil
    end
  end
end
