require 'spec_helper'
require 'svea_payments'
require 'date'

RSpec.describe SveaPayments::Reports, :type => :request do
  before do
    WebMock.allow_net_connect!
  end
  
  after do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  describe '.get_compensation_report' do
    let(:username) { 'ILQXQZEI' }
    let(:password) { 'Pyq8kd5CFSMSuCxate26xHw73edZyg2ytUQMqJPQ' }
    let(:token) { SveaPayments::Authentication.get_basic_auth_token(username, password) }
    let(:seller_id) { 'ILQXQZEI' }
    let(:start_date) { Date.new(2024, 11, 1) }
    let(:end_date) { Date.new(2024, 11, 30) }

    it 'successfully retrieves compensation report in XML format' do
      response = described_class.get_compensation_report(start_date, end_date, seller_id, token)
      puts response.inspect
      # Verify response structure
      expect(response).to include(
        'version',
        'timestamp',
        'sellerId',
        'resultCode',
        'resultText',
        'keyGeneration',
        'compensations'
      )

      # Verify compensations array structure
      expect(response['compensations']).to be_an(Array)
      
      if response['compensations'].any?
        compensation = response['compensations'].first
        expect(compensation).to include(
          'compensationCode',
          'compensationType',
          'compensationDate',
          'reference',
          'grossAmount',
          'netAmount',
          'refundedAmount',
          'commission',
          'commissionVat',
          'orders'
        )

        # Verify orders structure if present
        if compensation['orders'].any?
          order = compensation['orders'].first
          expect(order).to include(
            'orderNumber',
            'originalReference',
            'paymentId',
            'sellerGrossAmount',
            'sellerNetAmount',
            'refundedAmount',
            'commission',
            'commissionVat',
            'commissionVatRate',
            'buyerPaymentDateTime',
            'paymentMethod',
            'paymentMethodGroup'
          )
        end
      end
    end

    it 'successfully retrieves compensation report in CSV format' do
      response = described_class.get_compensation_report(
        start_date, 
        end_date, 
        seller_id, 
        token, 
        format: 'CSV'
      )
      
      # Verify it returns Nokogiri XML object for CSV response
      expect(response).to be_a(Nokogiri::XML::Document)
    end

    it 'handles string dates correctly' do
      response = described_class.get_compensation_report(
        '01.11.2023',
        '30.11.2023',
        seller_id,
        token
      )
      
      expect(response).to include('resultCode')
      expect(response['resultCode']).not_to be_nil
    end

    it 'handles Date objects correctly' do
      response = described_class.get_compensation_report(
        Date.new(2023, 11, 1),
        Date.new(2023, 11, 30),
        seller_id,
        token
      )
      
      expect(response).to include('resultCode')
      expect(response['resultCode']).not_to be_nil
    end

    it 'handles custom key generation' do
      response = described_class.get_compensation_report(
        start_date,
        end_date,
        seller_id,
        token,
        key_generation: '002'
      )
      
      expect(response).to include('keyGeneration')
      expect(response['keyGeneration']).not_to be_nil
    end

    context 'with invalid parameters' do
      it 'handles invalid date format gracefully' do
        expect {
          described_class.get_compensation_report(
            'invalid-date',
            end_date,
            seller_id,
            token
          )
        }.not_to raise_error
      end

      it 'handles invalid seller_id gracefully' do
        response = described_class.get_compensation_report(
          start_date,
          end_date,
          'INVALID_SELLER_ID',
          token
        )
        
        expect(response).to include('resultCode')
        expect(response['resultCode']).not_to eq('00') # Assuming '00' is success code
      end
    end
  end
end 