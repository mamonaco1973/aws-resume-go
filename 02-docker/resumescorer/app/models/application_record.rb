# Every model class in the app inherits from ApplicationRecord instead
# of ActiveRecord::Base directly. This indirection lets us add shared
# model behaviour in one place (custom validations, common concerns, a
# global default scope) without monkey-patching Rails itself.
#
# primary_abstract_class tells ActiveRecord that this class has no
# corresponding database table — there is no "application_records" table.
# Without this declaration, ActiveRecord would try to introspect a table
# that does not exist and raise an error on startup.
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
