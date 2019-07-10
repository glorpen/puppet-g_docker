RSpec.configure do |config|
  config.mock_with :rspec
  config.after(:suite) do
    RSpec::Puppet::Coverage.report!(0)
  end
end
