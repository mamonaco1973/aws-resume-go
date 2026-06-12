class CreateJobApplications < ActiveRecord::Migration[7.1]
  def change
    create_table :attachments do |t|
      t.references :job,  null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string     :filename,  null: false
      t.text       :notes
      t.timestamps
    end
  end
end
