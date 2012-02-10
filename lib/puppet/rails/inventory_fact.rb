require 'puppet/rails/inventory_node'

class Puppet::Rails::InventoryFact < ::ActiveRecord::Base
  include Puppet::Util::ReferenceSerializer
  extend Puppet::Util::ReferenceSerializer

  belongs_to :node, :class_name => "Puppet::Rails::InventoryNode"

  def value
    # Because rails doesn't deserialize for you
    unserialize_value(self[:value])
  end

  def value=(val)
    # Rails will normally serialize for you, but this ensures it
    self[:value] = serialize_value(val)
  end
end
