# ==============================================================================
# Folder
# A named bucket for organising jobs on the dashboard. Purely cosmetic —
# scoring does not change based on which folder a job is in. Deleting a
# folder does not delete its jobs; it sets their folder_id to NULL so
# they appear in the "unfiled" view.
# ==============================================================================
class Folder < ApplicationRecord
  belongs_to :user

  # dependent: :nullify preserves the jobs inside a deleted folder.
  # Jobs lose their folder assignment but all scoring data remains intact.
  # Using dependent: :destroy here would silently delete scored jobs,
  # which would be a destructive surprise for the user.
  has_many :jobs, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }
end
