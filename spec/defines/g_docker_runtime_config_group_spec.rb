require 'spec_helper'

describe 'G_docker::Runtime_config::Group' do
  let(:title) { 'test' }
  let(:params) do
    {
      'container' => 'example',
    }
  end
  let(:pre_condition) do
    [
      'class {"g_docker": data_vg_name => "vg_test", runtime_config_path => "/config.d" }',
      'g_docker::compat::run {"example": image => "example", ensure => "present"}',
      'g_docker::runtime_config {"example": reload_signal => "HUP"}',
    ]
  end

  before(:each) do
    Puppet::Parser::Functions.newfunction(:assert_private, type: :rvalue) { |args| }
  end

  context 'with source reload' do
    let(:params) do
      super().merge('source' => 'puppet://g_docker/test')
    end

    context 'disabled' do
      let(:params) do
        super().merge('source_reload' => false)
      end

      it { is_expected.to contain_file('/config.d/example/test').that_notifies('G_docker::Compat::Run[example]') }
    end

    context 'enabled' do
      let(:params) do
        super().merge('source_reload' => true)
      end

      it { is_expected.to contain_file('/config.d/example/test').that_notifies('Exec[g_docker runtime config example]') }
    end
  end
end
