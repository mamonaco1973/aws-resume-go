class CreateCompanies < ActiveRecord::Migration[7.1]
  def change
    create_table :folders do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :name, null: false
      t.timestamps
    end
  end
end
