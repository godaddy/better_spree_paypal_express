require 'spec_helper'

module PayPal::SDK::Merchant::Urls
  REDIRECT_ENDPOINTS = { :sandbox => "https://www.sandbox.paypal.com/webapps/xo/webflow/sparta/xoflow" }

  def express_checkout_url(token, extra_params={})
    token = token.Token if token.respond_to?(:Token)
    params = {:token => token.to_s, :fallback => 1}
    redirect_url(params.merge!(extra_params))
  end
end

describe "PayPal", :js => true do
  let!(:product) { FactoryGirl.create(:product, :name => 'iPad') }
  before do
    @gateway = Spree::Gateway::PayPalExpress.create!({
      :preferred_login => "pp_api1.ryanbigg.com",
      :preferred_password => "1383066713",
      :preferred_signature => "An5ns1Kso7MWUdW4ErQKJJJ4qi4-Ar-LpzhMJL0cu8TjM8Z2e1ykVg5B",
      :name => "PayPal",
      :active => true,
      :environment => Rails.env
    })
    FactoryGirl.create(:shipping_method)
  end

  def fill_in_billing
    within("#billing") do
      fill_in "First Name", :with => "Test"
      fill_in "Last Name", :with => "User"
      fill_in "Street Address", :with => "1 User Lane"
      # City, State and ZIP must all match for PayPal to be happy
      fill_in "City", :with => "Adamsville"
      select "United States of America", :from => "order_bill_address_attributes_country_id"
      select "Alabama", :from => "order_bill_address_attributes_state_id"
      fill_in "Zip", :with => "35005"
      fill_in "Phone", :with => "555-AME-RICA"
    end
  end

  def switch_to_paypal_login
    # If you go through a payment once in the sandbox, it remembers your preferred setting.
    # It defaults to the *wrong* setting for the first time, so we need to have this method.
    unless page.has_selector?("#login_email")
      find("#loadLogin").click
    end
  rescue Capybara::Poltergeist::JavascriptError => e
    Rails.logger.error "Errors IGNORED for this page - #{e.message}"
  end

  def find_and_click_paypal_button
    find("#paypal_button").click
  rescue Capybara::Poltergeist::JavascriptError => e
    Rails.logger.error "Errors IGNORED for this page - #{e.message}"
  end

  def login_to_paypal
    fill_in "email", :with => "pp@spreecommerce.com"
    fill_in "password", :with => "thequickbrownfox"
    click_button "Log in to PayPal"
  end

  it "pays for an order successfully" do
    visit spree.root_path
    click_link 'iPad'
    click_button 'Add To Cart'
    click_button 'Checkout'
    within("#guest_checkout") do
      fill_in "Email", :with => "test@example.com"
      click_button 'Continue'
    end
    fill_in_billing
    click_button "Save and Continue"
    # Delivery step doesn't require any action
    click_button "Save and Continue"
    find_and_click_paypal_button
    login_to_paypal
    click_button "Pay Now"
    page.should have_content("Your order has been processed successfully")

    Spree::Payment.last.source.transaction_id.should_not be_blank
  end

  it "includes adjustments in PayPal summary" do
    visit spree.root_path
    click_link 'iPad'
    click_button 'Add To Cart'
    # TODO: Is there a better way to find this current order?
    order = Spree::Order.last
    order.adjustments.create!(:amount => -5, :label => "$5 off")
    order.adjustments.create!(:amount => 10, :label => "$10 on")
    visit '/cart'
    within("#cart_adjustments") do
      page.should have_content("$5 off")
      page.should have_content("$10 on")
    end
    click_button 'Checkout'
    within("#guest_checkout") do
      fill_in "Email", :with => "test@example.com"
      click_button 'Continue'
    end
    fill_in_billing
    click_button "Save and Continue"
    # Delivery step doesn't require any action
    click_button "Save and Continue"
    find_and_click_paypal_button
    login_to_paypal
    find("#transactionCart").click
    within(".transctionCartDetails") do
      page.should have_content("$5 off")
      page.should have_content("$10 on")
    end
  end

  context "line item adjustments" do
    let(:promotion) { Spree::Promotion.create(name: "10% off") }
    before do
      calculator = Spree::Calculator::FlatPercentItemTotal.new(preferred_flat_percent: 10)
      action = Spree::Promotion::Actions::CreateItemAdjustments.create(:calculator => calculator)
      promotion.actions << action
    end

    it "includes line item adjustments in PayPal summary" do

      visit spree.root_path
      click_link 'iPad'
      click_button 'Add To Cart'
      # TODO: Is there a better way to find this current order?
      order = Spree::Order.last
      order.line_item_adjustments.count.should == 1

      visit '/cart'
      within("#cart_adjustments") do
        page.should have_content("10% off")
      end
      click_button 'Checkout'
      within("#guest_checkout") do
        fill_in "Email", :with => "test@example.com"
        click_button 'Continue'
      end
      fill_in_billing
      click_button "Save and Continue"
      # Delivery step doesn't require any action
      click_button "Save and Continue"
      find_and_click_paypal_button
      find("#transactionCart").click
      within(".transctionCartDetails") do
        page.should have_content("10% off")
      end
    end
  end

  # Regression test for #10
  context "will skip $0 items" do
    let!(:product2) { FactoryGirl.create(:product, :name => 'iPod') }

    specify do
      visit spree.root_path
      click_link 'iPad'
      click_button 'Add To Cart'

      visit spree.root_path
      click_link 'iPod'
      click_button 'Add To Cart'

      # TODO: Is there a better way to find this current order?
      order = Spree::Order.last
      order.line_items.last.update_attribute(:price, 0)
      click_button 'Checkout'
      within("#guest_checkout") do
        fill_in "Email", :with => "test@example.com"
        click_button 'Continue'
      end
      fill_in_billing
      click_button "Save and Continue"
      # Delivery step doesn't require any action
      click_button "Save and Continue"
      find_and_click_paypal_button
      find("#transactionCart").click
      within(".transctionCartDetails") do
        page.should have_content('iPad')
        page.should_not have_content('iPod')
      end
    end
  end

  context "can process an order with $0 item total" do
    before do
      # If we didn't do this then the order would be free and skip payment altogether
      calculator = Spree::ShippingMethod.first.calculator
      calculator.preferred_amount = 10
      calculator.save
    end

    specify do
      visit spree.root_path
      click_link 'iPad'
      click_button 'Add To Cart'
      # TODO: Is there a better way to find this current order?
      order = Spree::Order.last
      order.adjustments.create!(:amount => -order.line_items.last.price, :label => "FREE iPad ZOMG!")
      click_button 'Checkout'
      within("#guest_checkout") do
        fill_in "Email", :with => "test@example.com"
        click_button 'Continue'
      end
      fill_in_billing
      click_button "Save and Continue"
      # Delivery step doesn't require any action
      click_button "Save and Continue"
      find_and_click_paypal_button
      within("#transactionCart") do
        page.should have_content('$10.00')
      end
    end
  end

  context "cannot process a payment with invalid gateway details" do
    before do
      @gateway.preferred_login = nil
      @gateway.save
    end

    specify do
      visit spree.root_path
      click_link 'iPad'
      click_button 'Add To Cart'
      click_button 'Checkout'
      within("#guest_checkout") do
        fill_in "Email", :with => "test@example.com"
        click_button 'Continue'
      end
      fill_in_billing
      click_button "Save and Continue"
      # Delivery step doesn't require any action
      click_button "Save and Continue"
      find_and_click_paypal_button
      page.should have_content("PayPal failed. Security header is not valid")
    end
  end

  context "as an admin" do
    stub_authorization!

    context "refunding payments" do
      before do
        visit spree.root_path
        click_link 'iPad'
        click_button 'Add To Cart'
        click_button 'Checkout'
        within("#guest_checkout") do
          fill_in "Email", :with => "test@example.com"
          click_button 'Continue'
        end
        fill_in_billing
        click_button "Save and Continue"
        # Delivery step doesn't require any action
        click_button "Save and Continue"
        find_and_click_paypal_button
        login_to_paypal
        click_button "Pay Now"
        using_wait_time(30.seconds) do
          page.should have_content("Your order has been processed successfully")
        end

        visit '/admin'
        @order_num = Spree::Order.last.number
        click_link @order_num
        click_link "Payments"
        find("#content").find("table").first("a").click # this clicks the first payment
        click_link "Refund"
      end

      it "can refund payments fully" do
        click_button "Refund"
        page.should have_content("PayPal refund successful")

        payment = Spree::Order.find_by_number(@order_num).payments.first
        source = payment.source
        source.refund_transaction_id.should_not be_blank
        source.refunded_at.should_not be_blank
        source.state.should eql("refunded")
        source.refund_type.should eql("Full")

        # regression test for #82
        within("table") do
          page.should have_content(payment.display_amount.to_html)
        end
      end

      it "can refund payments partially" do
        payment = Spree::Order.find_by_number(@order_num).payments.first
        # Take a dollar off, which should cause refund type to be...
        fill_in "Amount", :with => payment.amount - 1
        click_button "Refund"
        page.should have_content("PayPal refund successful")

        source = payment.source
        source.refund_transaction_id.should_not be_blank
        source.refunded_at.should_not be_blank
        source.state.should eql("refunded")
        # ... a partial refund
        source.refund_type.should eql("Partial")
      end

      it "errors when given an invalid refund amount" do
        fill_in "Amount", :with => "lol"
        click_button "Refund"
        page.should have_content("PayPal refund unsuccessful (The partial refund amount is not valid)")
      end
    end
  end
end
