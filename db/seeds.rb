# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Nothing to seed. The reserved categories ("outros", "cartão de crédito") are
# one person's, not the database's — they are created per person by
# SetupController on first-run setup. A seed running with no Current.user would
# fail OwnedByUser's `belongs_to :user` outright.
