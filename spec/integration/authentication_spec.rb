require 'spec_helper'

RSpec.describe 'SveaPayments Authentication Integration' do
  context 'Authentication' do
    it 'successfully authenticates and returns a token' do
      username = 'ILQXQZEI'
      password = 'Pyq8kd5CFSMSuCxate26xHw73edZyg2ytUQMqJPQ'
      token = SveaPayments::Authentication.get_basic_auth_token(username, password)
      expect(token).to eq("Basic SUxRWFFaRUk6UHlxOGtkNUNGU01TdUN4YXRlMjZ4SHc3M2VkWnlnMnl0VVFNcUpQUQ==")
    end
  end
end
