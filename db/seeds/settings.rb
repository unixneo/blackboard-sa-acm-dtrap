# db/seeds/settings.rb
#
# Seeds default settings. Skips keys that already exist in the DB.
# Safe to run at any time on any system.

Setting.seed_defaults!
puts "Settings seeded"
