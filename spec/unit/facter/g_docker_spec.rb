require 'spec_helper'
require 'g_docker_util/http_unix'

describe 'g_docker', type: :fact do
  before(:each) { Facter.clear }
  after(:each) { Facter.clear }

  let(:double_http) { instance_double(NetX::HTTPUnix) }

  context 'with docker not running' do
    it { expect(Facter.fact(:g_docker).value).to include('installed' => false, 'version' => nil) }
  end
  describe 'with docker running' do
    before(:each) do
      allow(NetX::HTTPUnix).to receive(:new).and_return(double_http)
      response1 = instance_double(Net::HTTPResponse)
      allow(response1).to receive(:body).and_return('{}')
      response2 = instance_double(Net::HTTPResponse)
      allow(response2).to receive(:body).and_return('{"Version":"18.9.5"}')
      allow(double_http).to receive(:request).and_return(response1, response2)
    end
    context 'with default version' do
      it { expect(Facter.fact(:g_docker).value).to include('installed' => true, 'version' => '18.9.5') }
    end
  end
end
