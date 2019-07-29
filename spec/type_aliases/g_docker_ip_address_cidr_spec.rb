require 'spec_helper'

describe 'G_docker::IP::Address::CIDR' do
  it { is_expected.to allow_value('192.168.0.0/24') }
  it { is_expected.to allow_value('fffe::/64') }
end
