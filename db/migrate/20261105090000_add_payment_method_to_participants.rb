class AddPaymentMethodToParticipants < ActiveRecord::Migration[8.1]
  def change
    add_column :participants, :payment_method, :string
  end
end
