# frozen_string_literal: true

RSpec.describe Spree::PaypalController, type: :controller do
  routes { Spree::Core::Engine.routes }

  context 'when current_order is nil' do
    before do
      allow_any_instance_of(described_class).to receive(:current_order).and_return(nil)
      allow_any_instance_of(described_class).to receive(:current_spree_user).and_return(nil)
    end

    context 'express' do
      it 'raises ActiveRecord::RecordNotFound' do
          expect { get :express }.
            to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'confirm' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect{ get :confirm }.
          to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
