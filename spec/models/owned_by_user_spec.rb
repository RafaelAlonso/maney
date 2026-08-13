require "rails_helper"

RSpec.describe OwnedByUser do
  it "stamps the current person on a new record" do
    create_setting!
    category = Category.create!(name: "mercado")

    expect(category.user).to eq(current_user)
  end

  it "hides another person's records" do
    create_setting!
    mine = Category.create!(name: "mercado")

    other = create_user!(email_address: "outra@example.com")
    theirs = nil
    previous = Current.session
    Current.session = Session.create!(user: other)
    theirs = Category.create!(name: "farmácia")
    Current.session = previous

    expect(Category.pluck(:id)).to include(mine.id)
    expect(Category.pluck(:id)).not_to include(theirs.id)
    expect { Category.find(theirs.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "answers nothing at all when nobody is signed in" do
    create_setting!
    Category.create!(name: "mercado")

    Current.session = nil

    expect(Category.count).to eq(0)
    expect(Setting.instance).to be_nil
  end

  it "gives each person their own Setting, despite the single-row rule" do
    create_setting!(first_month: Date.new(2026, 3, 1))

    other = create_user!(email_address: "outra@example.com")
    Current.session = Session.create!(user: other)

    expect { Setting.create!(first_month: Date.new(2026, 5, 1)) }.not_to raise_error
    expect(Setting.instance.first_month).to eq(Date.new(2026, 5, 1))
  end

  # The guard that outlives this story: a table added later cannot join the
  # schema unscoped without failing here.
  describe "the schema" do
    # `invitations` is exempt on purpose, not by oversight: an invitation exists
    # before anyone owns it and belongs to the group rather than to a budget.
    # Its `invited_by_id` is provenance and scopes nothing.
    #
    # `solid_queue_*` tables are exempt for the same reason as `sessions`:
    # infrastructure the whole app shares, not budgeting data belonging to any
    # one person. Solid Queue owns their schema (a migration copied verbatim
    # from the gem, per its single-database install path) and its own models,
    # neither of which this app's `OwnedByUser` convention should reach into.
    exempt = %w[users sessions invitations schema_migrations ar_internal_metadata]

    it "requires a person on every table that holds budgeting data" do
      tables = ActiveRecord::Base.connection.tables - exempt
      tables = tables.reject { |table| table.start_with?("solid_queue_") }

      tables.each do |table|
        column = ActiveRecord::Base.connection.columns(table).find { |c| c.name == "user_id" }
        expect(column).to be_present, "#{table} has no user_id"
        expect(column.null).to be(false), "#{table}.user_id is nullable"
      end
    end

    it "scopes every model backed by one of those tables" do
      tables = ActiveRecord::Base.connection.tables - exempt
      tables = tables.reject { |table| table.start_with?("solid_queue_") }
      Rails.application.eager_load!

      ActiveRecord::Base.descendants.select { |model| tables.include?(model.table_name) }.each do |model|
        expect(model.include?(OwnedByUser)).to be(true), "#{model} does not include OwnedByUser"
      end
    end
  end

  it "lets two people each keep their own reserved categories" do
    create_reserved_categories!

    other = create_user!(email_address: "outra@example.com")
    Current.session = Session.create!(user: other)

    expect { create_reserved_categories! }.not_to raise_error
    expect(Category.unscoped.where(role: "others").count).to eq(2)
  end
end
