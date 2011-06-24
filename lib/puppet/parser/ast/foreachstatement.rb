require 'puppet/parser/ast/branch'
require 'puppet/type/whit'

class Puppet::Parser::AST
  class ForeachStatement < AST::Branch
     attr_accessor :data, :statements

     associates_doc

     def evaluate(scope)

       @data.safeevaluate(scope).each { |item|
         foo = Puppet::Resource.new("Whit", "foreach_#{item}")
         newsc = scope.newscope(:resource => foo)
         parsewrap do
           newsc.setvar("item", item)
         end
         @statements.safeevaluate(newsc)
       }
     end

  end
end
