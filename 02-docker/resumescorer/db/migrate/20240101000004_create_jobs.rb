class CreateJobs < ActiveRecord::Migration[7.1]
  def change
    create_table :jobs do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :resume, null: false, foreign_key: true
      t.references :folder, foreign_key: true

      t.string  :title,               default: ""
      t.string  :company,             default: ""
      t.string  :source_type,         null: false
      t.string  :url
      t.text    :raw_text
      # Bedrock-cleaned job description stored after extraction
      t.text    :job_description_text
      t.integer :score
      # Overview/Strengths/Weaknesses analysis from Bedrock
      t.text    :analysis
      t.string  :status,              null: false, default: "pending"
      t.string  :status_message,      default: ""
      t.text    :notes
      t.integer :tokens_used,         null: false, default: 0
      t.timestamps
    end

    add_index :jobs, :status
    add_index :jobs, :created_at
  end
end
