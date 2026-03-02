# db/seeds.rb — orchestrator for fresh installs only
#
# WARNING: Do NOT run on an existing installation.
# db/seeds/ks.rb guards operator-customized fields (system_prompt, provider,
# model) on existing records, but running the full seed on a live system is
# still discouraged. Use the individual seed files instead:
#
#   bin/rails runner "load Rails.root.join('db/seeds/settings.rb')"
#   bin/rails runner "load Rails.root.join('db/seeds/ks.rb')"
#   bin/rails runner "load Rails.root.join('db/seeds/sensors.rb')"

load Rails.root.join('db/seeds/settings.rb')
load Rails.root.join('db/seeds/ks.rb')
load Rails.root.join('db/seeds/sensors.rb')
load Rails.root.join('db/seeds/domain_sensors.rb')
