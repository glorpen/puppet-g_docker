require 'spec_helper'

describe 'G_docker' do
  let(:params) do
    {
      'data_vg_name' => 'vg-example',
    }
  end

  context 'with defaults' do
    it { is_expected.to compile }
  end
end
