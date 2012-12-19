require 'puppet/module_tool'

module Puppet::ModuleTool
  module Applications
    require 'puppet/module_tool/applications/application'
    require 'puppet/module_tool/applications/installer'
    require 'puppet/module_tool/applications/unpacker'
  end
end
