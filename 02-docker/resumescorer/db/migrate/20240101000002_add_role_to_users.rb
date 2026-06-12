class AddRoleToUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :resumes do |t|
      t.references :user,         null: false, foreign_key: true
      t.string     :name,         null: false
      # Extracted text stored in DB — avoids re-reading the attachment on
      # every scoring job. Populated at upload time via pdf-reader.
      t.text       :content_text
      t.timestamps
    end
  end
end
