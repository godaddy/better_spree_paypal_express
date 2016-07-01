describe Spree::Gateway::PayPalExpress do

  let(:gateway) { Spree::Gateway::PayPalExpress.create!(name: "PayPalExpress", :environment => Rails.env) }

  context "payment purchase" do

    let(:bn_code) { nil }
    let(:token) { "fake_token" }
    let(:currency_id) { "USD" }
    let(:payment_action) { "Sale" }
    let(:payer_id) { "fake_payer_id" }
    let(:order_value) { "10.00" }
    let(:transaction_id) { "12345" }

    let(:payment) do
      payment = FactoryGirl.create(:payment, :payment_method => gateway, :amount => 10)
      allow(payment).to receive(:source).and_return(mock_model(Spree::PaypalExpressCheckout, :token => token, :payer_id => payer_id, :update_column => true))
      payment
    end

    let(:provider) do
      provider = double('Provider')
      allow(gateway).to receive(:provider).and_return(provider)
      provider
    end

    let(:pp_details_request) { double }

    before do
      expect(provider).to receive(:build_get_express_checkout_details).
          with({ Token: token }).
          and_return(pp_details_request)

      pp_details_response = double(:get_express_checkout_details_response_details =>
        double(:PaymentDetails => {
          OrderTotal: {
            currencyID: currency_id,
            value: order_value
          },
        }, payment_details: []))

      expect(provider).to receive(:get_express_checkout_details).
        with(pp_details_request).
        and_return(pp_details_response)

      expect(provider).to receive(:build_do_express_checkout_payment).with({
        :DoExpressCheckoutPaymentRequestDetails => {
          PaymentAction: payment_action,
          Token: token,
          PayerID: payer_id,
          PaymentDetails: pp_details_response.get_express_checkout_details_response_details.PaymentDetails,
          ButtonSource: bn_code
        }
      })
    end

    # Test for #11
    context "payment succeeds" do

      before do
        response = double('pp_response', :success? => true)
        response.stub_chain("do_express_checkout_payment_response_details.payment_info.first.transaction_id").and_return transaction_id
        allow(provider).to receive(:do_express_checkout_payment).and_return(response)
      end

      it "completes without error" do
        expect { payment.purchase! }.to_not raise_error
      end

      context "with button source defined" do

        let(:bn_code) { "TEST BN CODE" }

        before { Spree::Gateway::PayPalExpress.button_source = bn_code }

        after { Spree::Gateway::PayPalExpress.button_source = nil }

        it "sets ButtonSource to configured BN Code" do
          payment.purchase!
        end

      end

    end

    context "payment fails" do

      before do
        # stub persist_invalid as it causes DatabaseCleaner.clean to go for a toss
        allow(payment).to receive(:persist_invalid).and_return(nil)
        response = double('pp_response', :success? => false, :errors => [double('pp_response_error', :long_message => "An error goes here.")])
        expect(provider).to receive(:do_express_checkout_payment).and_return(response)
      end

      it "raises GatewayError" do
        expect { payment.purchase! }.to raise_error(Spree::Core::GatewayError, "An error goes here.")
      end

    end

  end
end
